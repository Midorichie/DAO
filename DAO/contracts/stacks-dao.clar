;; DAO Smart Contract - Initial Implementation
;; Version: 1.0.0

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-MEMBER (err u101))
(define-constant ERR-NOT-MEMBER (err u102))
(define-constant ERR-INVALID-PROPOSAL (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-PROPOSAL-EXPIRED (err u105))

;; Data Variables
(define-data-var minimum-stake uint u100000) ;; Minimum STX required for membership
(define-data-var proposal-duration uint u1440) ;; Duration in blocks (roughly 10 days)
(define-data-var quorum-percentage uint u51) ;; 51% required for proposal to pass

;; Data Maps
(define-map members principal bool)
(define-map member-stakes principal uint)

(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-ascii 50),
        description: (string-ascii 500),
        start-block: uint,
        end-block: uint,
        executed: bool,
        yes-votes: uint,
        no-votes: uint,
        total-votes: uint
    }
)

(define-map votes {proposal-id: uint, voter: principal} bool)

;; Counter for proposal IDs
(define-data-var proposal-counter uint u0)

;; Membership Functions
(define-public (join-dao)
    (let
        (
            (stake-amount (unwrap! (stx-get-balance tx-sender) ERR-NOT-AUTHORIZED))
        )
        (asserts! (>= stake-amount (var-get minimum-stake)) ERR-NOT-AUTHORIZED)
        (asserts! (not (default-to false (map-get? members tx-sender))) ERR-ALREADY-MEMBER)
        
        (try! (stx-transfer? (var-get minimum-stake) tx-sender (as-contract tx-sender)))
        (map-set members tx-sender true)
        (map-set member-stakes tx-sender (var-get minimum-stake))
        (ok true)
    )
)

(define-public (leave-dao)
    (let
        (
            (stake (default-to u0 (map-get? member-stakes tx-sender)))
        )
        (asserts! (default-to false (map-get? members tx-sender)) ERR-NOT-MEMBER)
        
        (try! (as-contract (stx-transfer? stake (as-contract tx-sender) tx-sender)))
        (map-delete members tx-sender)
        (map-delete member-stakes tx-sender)
        (ok true)
    )
)

;; Proposal Functions
(define-public (create-proposal (title (string-ascii 50)) (description (string-ascii 500)))
    (let
        (
            (proposal-id (+ (var-get proposal-counter) u1))
            (start-block block-height)
            (end-block (+ block-height (var-get proposal-duration)))
        )
        (asserts! (default-to false (map-get? members tx-sender)) ERR-NOT-MEMBER)
        
        (map-set proposals proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            start-block: start-block,
            end-block: end-block,
            executed: false,
            yes-votes: u0,
            no-votes: u0,
            total-votes: u0
        })
        
        (var-set proposal-counter proposal-id)
        (ok proposal-id)
    )
)

(define-public (vote (proposal-id uint) (vote-bool bool))
    (let
        (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-INVALID-PROPOSAL))
            (has-voted (default-to false (map-get? votes {proposal-id: proposal-id, voter: tx-sender})))
        )
        (asserts! (default-to false (map-get? members tx-sender)) ERR-NOT-MEMBER)
        (asserts! (not has-voted) ERR-ALREADY-VOTED)
        (asserts! (<= block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        
        (map-set votes {proposal-id: proposal-id, voter: tx-sender} true)
        
        (map-set proposals proposal-id
            (merge proposal
                {
                    yes-votes: (if vote-bool (+ (get yes-votes proposal) u1) (get yes-votes proposal)),
                    no-votes: (if vote-bool (get no-votes proposal) (+ (get no-votes proposal) u1)),
                    total-votes: (+ (get total-votes proposal) u1)
                }
            )
        )
        (ok true)
    )
)

;; Read-Only Functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-member-status (member principal))
    (default-to false (map-get? members member))
)

(define-read-only (get-member-stake (member principal))
    (default-to u0 (map-get? member-stakes member))
)

(define-read-only (has-voted (proposal-id uint) (voter principal))
    (default-to false (map-get? votes {proposal-id: proposal-id, voter: voter}))
)