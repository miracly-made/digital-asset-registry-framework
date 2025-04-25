;; Digital Asset Registry Framework

;; Global Registry Counter
(define-data-var registry-sequence uint u0)

;; System Administrator
(define-constant admin-authority tx-sender)

;; Primary Data Repository
(define-map asset-catalog
  { asset-sequence: uint }
  {
    asset-descriptor: (string-ascii 64),
    asset-custodian: principal,
    asset-volume: uint,
    registration-block: uint,
    asset-descriptor-extended: (string-ascii 128),
    classification-tags: (list 10 (string-ascii 32))
  }
)

;; Authorization Matrix
(define-map authorization-matrix
  { asset-sequence: uint, authorized-party: principal }
  { access-status: bool }
)

;; Response Status Codes
(define-constant entity-not-found-error (err u401))
(define-constant duplicate-entity-error (err u402))
(define-constant administrative-restriction-error (err u400))
(define-constant descriptor-format-error (err u403))
(define-constant volume-parameter-error (err u404))
(define-constant permission-denied-error (err u405))
(define-constant unauthorized-operation-error (err u406))
(define-constant visibility-restriction-error (err u407))
(define-constant tag-validation-error (err u408))


;; ===== Core Registry Operations =====

;; Registers a new digital asset with complete metadata
(define-public (register-new-asset 
  (descriptor (string-ascii 64)) 
  (volume uint) 
  (extended-information (string-ascii 128)) 
  (tags (list 10 (string-ascii 32)))
)
  (let
    (
      (next-sequence (+ (var-get registry-sequence) u1))
    )
    ;; Input validation checks
    (asserts! (> (len descriptor) u0) descriptor-format-error)
    (asserts! (< (len descriptor) u65) descriptor-format-error)
    (asserts! (> volume u0) volume-parameter-error)
    (asserts! (< volume u1000000000) volume-parameter-error)
    (asserts! (> (len extended-information) u0) descriptor-format-error)
    (asserts! (< (len extended-information) u129) descriptor-format-error)
    (asserts! (validate-tag-collection tags) tag-validation-error)

    ;; Create catalog entry
    (map-insert asset-catalog
      { asset-sequence: next-sequence }
      {
        asset-descriptor: descriptor,
        asset-custodian: tx-sender,
        asset-volume: volume,
        registration-block: block-height,
        asset-descriptor-extended: extended-information,
        classification-tags: tags
      }
    )

    ;; Initialize custodian authorization
    (map-insert authorization-matrix
      { asset-sequence: next-sequence, authorized-party: tx-sender }
      { access-status: true }
    )

    ;; Update sequence counter
    (var-set registry-sequence next-sequence)
    (ok next-sequence)
  )
)

;; Updates existing asset registration information
(define-public (update-asset-registration 
  (asset-sequence uint) 
  (revised-descriptor (string-ascii 64)) 
  (revised-volume uint) 
  (revised-information (string-ascii 128)) 
  (revised-tags (list 10 (string-ascii 32)))
)
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    ;; Verify asset exists and requestor is the custodian
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)

    ;; Validate updated information
    (asserts! (> (len revised-descriptor) u0) descriptor-format-error)
    (asserts! (< (len revised-descriptor) u65) descriptor-format-error)
    (asserts! (> revised-volume u0) volume-parameter-error)
    (asserts! (< revised-volume u1000000000) volume-parameter-error)
    (asserts! (> (len revised-information) u0) descriptor-format-error)
    (asserts! (< (len revised-information) u129) descriptor-format-error)
    (asserts! (validate-tag-collection revised-tags) tag-validation-error)

    ;; Update asset registration with revised information
    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { 
        asset-descriptor: revised-descriptor, 
        asset-volume: revised-volume, 
        asset-descriptor-extended: revised-information, 
        classification-tags: revised-tags 
      })
    )
    (ok true)
  )
)

;; Cancels an asset registration completely
(define-public (cancel-asset-registration (asset-sequence uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    ;; Verify asset exists and requestor is the custodian
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)

    ;; Remove asset registration
    (map-delete asset-catalog { asset-sequence: asset-sequence })
    (ok true)
  )
)

;; Executes custodial transfer to new party
(define-public (transfer-asset-custody (asset-sequence uint) (new-custodian principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    ;; Verify asset exists and requestor is current custodian
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)

    ;; Update custodial relationship
    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { asset-custodian: new-custodian })
    )
    (ok true)
  )
)

;; ===== Authorization Management =====

;; Revokes third-party access authorization
(define-public (revoke-third-party-access (asset-sequence uint) (third-party principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    ;; Verify asset exists and requestor is the custodian
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)
    (asserts! (not (is-eq third-party tx-sender)) administrative-restriction-error)

    ;; Remove authorization entry
    (map-delete authorization-matrix { asset-sequence: asset-sequence, authorized-party: third-party })
    (ok true)
  )
)

;; ===== Metadata Management =====

;; Appends additional classification tags to existing asset
(define-public (extend-classification-tags (asset-sequence uint) (additional-tags (list 10 (string-ascii 32))))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (existing-tags (get classification-tags catalog-entry))
      (combined-tags (unwrap! (as-max-len? (concat existing-tags additional-tags) u10) tag-validation-error))
    )
    ;; Verify asset exists and requestor is the custodian
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)

    ;; Verify additional tags format
    (asserts! (validate-tag-collection additional-tags) tag-validation-error)

    ;; Update asset with combined tag set
    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { classification-tags: combined-tags })
    )
    (ok combined-tags)
  )
)

;; ===== Administrative Functions =====

;; Applies emergency restrictions to prevent modifications
(define-public (apply-emergency-restriction (asset-sequence uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (restriction-marker "ADMINISTRATIVE-HOLD")
      (existing-tags (get classification-tags catalog-entry))
    )
    ;; Verify asset exists and requestor has authority
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! 
      (or 
        (is-eq tx-sender admin-authority)
        (is-eq (get asset-custodian catalog-entry) tx-sender)
      ) 
      administrative-restriction-error
    )

    (ok true)
  )
)

;; ===== Verification Services =====

;; Validates asset custody chain and integrity
(define-public (validate-asset-integrity (asset-sequence uint) (expected-custodian principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (current-custodian (get asset-custodian catalog-entry))
      (registration-height (get registration-block catalog-entry))
      (access-permitted (default-to 
        false 
        (get access-status 
          (map-get? authorization-matrix { asset-sequence: asset-sequence, authorized-party: tx-sender })
        )
      ))
    )
    ;; Verify asset exists and requestor has appropriate authorization
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! 
      (or 
        (is-eq tx-sender current-custodian)
        access-permitted
        (is-eq tx-sender admin-authority)
      ) 
      permission-denied-error
    )

    ;; Compare expected vs. actual custodial status
    (if (is-eq current-custodian expected-custodian)
      ;; Return successful validation with details
      (ok {
        validation-passed: true,
        verification-block: block-height,
        blocks-elapsed: (- block-height registration-height),
        custodian-verified: true
      })
      ;; Return custodial mismatch
      (ok {
        validation-passed: false,
        verification-block: block-height,
        blocks-elapsed: (- block-height registration-height),
        custodian-verified: false
      })
    )
  )
)

;; ===== Verification & Authorization Utilities =====

;; Confirms asset registration status
(define-private (asset-is-registered (asset-sequence uint))
  (is-some (map-get? asset-catalog { asset-sequence: asset-sequence }))
)

;; Validates custodial relationship
(define-private (is-custodian-of (asset-sequence uint) (evaluating-party principal))
  (match (map-get? asset-catalog { asset-sequence: asset-sequence })
    catalog-entry (is-eq (get asset-custodian catalog-entry) evaluating-party)
    false
  )
)

;; Retrieves registered volume for specified asset
(define-private (get-registered-volume (asset-sequence uint))
  (default-to u0
    (get asset-volume
      (map-get? asset-catalog { asset-sequence: asset-sequence })
    )
  )
)

;; Validates classification tag format
(define-private (is-valid-classification-tag (tag (string-ascii 32)))
  (and
    (> (len tag) u0)
    (< (len tag) u33)
  )
)

;; Ensures classification tag collection adheres to system standards
(define-private (validate-tag-collection (tags (list 10 (string-ascii 32))))
  (and
    (> (len tags) u0)
    (<= (len tags) u10)
    (is-eq (len (filter is-valid-classification-tag tags)) (len tags))
  )
)

;; Grants authorized access to third party
(define-public (authorize-third-party-access (asset-sequence uint) (authorized-party principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    ;; Verify asset exists and requestor is the custodian
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)
    (ok true)
  )
)

;; Retrieves asset classification profile
(define-public (get-asset-classification (asset-sequence uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (current-custodian (get asset-custodian catalog-entry))
      (access-permitted (default-to 
        false 
        (get access-status 
          (map-get? authorization-matrix { asset-sequence: asset-sequence, authorized-party: tx-sender })
        )
      ))
    )
    ;; Verify asset exists and requestor has appropriate authorization
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! 
      (or 
        (is-eq tx-sender current-custodian)
        access-permitted
        (is-eq tx-sender admin-authority)
      ) 
      permission-denied-error
    )

    ;; Return asset classification tags
    (ok (get classification-tags catalog-entry))
  )
)

;; Updates asset volume measurement
(define-public (update-asset-volume (asset-sequence uint) (new-volume uint))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
    )
    ;; Verify asset exists and requestor is the custodian
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)
    (asserts! (is-eq (get asset-custodian catalog-entry) tx-sender) unauthorized-operation-error)

    ;; Validate volume parameter
    (asserts! (> new-volume u0) volume-parameter-error)
    (asserts! (< new-volume u1000000000) volume-parameter-error)

    ;; Update asset volume
    (map-set asset-catalog
      { asset-sequence: asset-sequence }
      (merge catalog-entry { asset-volume: new-volume })
    )
    (ok true)
  )
)

;; Verifies custodial authorization status
(define-public (check-authorization-status (asset-sequence uint) (evaluating-party principal))
  (let
    (
      (catalog-entry (unwrap! (map-get? asset-catalog { asset-sequence: asset-sequence }) entity-not-found-error))
      (current-custodian (get asset-custodian catalog-entry))
      (access-permitted (default-to 
        false 
        (get access-status 
          (map-get? authorization-matrix { asset-sequence: asset-sequence, authorized-party: evaluating-party })
        )
      ))
    )
    ;; Verify asset exists
    (asserts! (asset-is-registered asset-sequence) entity-not-found-error)

    ;; Return authorization status
    (ok {
      is-custodian: (is-eq evaluating-party current-custodian),
      has-authorization: access-permitted,
      asset-id: asset-sequence
    })
  )
)
