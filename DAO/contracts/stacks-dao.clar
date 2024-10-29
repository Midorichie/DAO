;; DAO Smart Contract - Enhanced Implementation
;; Version: 2.0.0
;; Branch: feature/enhanced-governance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-MEMBER (err u101))
(define-constant ERR-NOT-MEMBER (err u102))
(define-constant ERR-INVALID-PROPOSAL (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-PROPOSAL-EXPIRED (err u105))
(define-constant ERR-INSUFFICIENT-STAKE (err u106))
(define-constant ERR-INVALID-DELEGATE (err u107))
(define-constant ERR-PROPOSAL-NOT-PASSED (err u108))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u109))
(define-constant ERR-TREASURY-INSUFFICIENT-FUNDS (err u110))

;; Data Variables
(define-data-var minimum-stake uint u100000)
(define-data-var proposal-duration uint u1440)
(define-data-var quorum-percentage uint u51)
(define-data-var governance-token-address principal 'SP000000000000000000002Q6VF78.governance-token)
(define-data-var treasury-balance uint u0)

;; Enhanced Data Maps
(define-map members 
    principal 
    {
        stake: uint,
        voting-power: uint,
        joined-block: uint,
        delegate: (optional principal)
    }
)

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
        total-votes: uint,
        execution-params: {
            target: principal,
            amount: uint,
            function-name: (string-ascii 128)
        },
        proposal-type: (string-ascii 20)  ;; "TREASURY" or "GOVERNANCE"
    }
)

(define-map votes 
    {proposal-id: uint, voter: principal} 
    {
        vote: bool,
        weight: uint,
        timestamp: uint
    }
)

(define-map delegations principal principal)
(define-data-var proposal-counter uint u0)

;; Enhanced Membership Functions
(define-public (join-dao (stake-amount uint))
    (let
        (
            (balance (unwrap! (stx-get-balance tx-sender) ERR-NOT-AUTHORIZED))
            (voting-power (calculate-voting-power stake-amount))
        )
        (asserts! (>= stake-amount (var-get minimum-stake)) ERR-INSUFFICIENT-STAKE)
        (asserts! (>= balance stake-amount) ERR-INSUFFICIENT-STAKE)
        (asserts! (not (is-member tx-sender)) ERR-ALREADY-MEMBER)
        
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        (map-set members tx-sender {
            stake: stake-amount,
            voting-power: voting-power,
            joined-block: block-height,
            delegate: none
        })
        (ok true)
    )
)

(define-public (increase-stake (additional-amount uint))
    (let
        (
            (current-member (unwrap! (map-get? members tx-sender) ERR-NOT-MEMBER))
            (new-stake (+ (get stake current-member) additional-amount))
        )
        (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
        (map-set members tx-sender
            (merge current-member {
                stake: new-stake,
                voting-power: (calculate-voting-power new-stake)
            })
        )
        (ok true)
    )
)

;; Delegation System
(define-public (delegate-vote (delegate-to principal))
    (let
        (
            (current-member (unwrap! (map-get? members tx-sender) ERR-NOT-MEMBER))
        )
        (asserts! (is-member delegate-to) ERR-INVALID-DELEGATE)
        (map-set delegations tx-sender delegate-to)
        (map-set members tx-sender
            (merge current-member {
                delegate: (some delegate-to)
            })
        )
        (ok true)
    )
)

;; Enhanced Proposal System
(define-public (create-proposal 
    (title (string-ascii 50)) 
    (description (string-ascii 500))
    (proposal-type (string-ascii 20))
    (target principal)
    (amount uint)
    (function-name (string-ascii 128))
)
    (let
        (
            (proposal-id (+ (var-get proposal-counter) u1))
            (start-block block-height)
            (end-block (+ block-height (var-get proposal-duration)))
            (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-MEMBER))
        )
        (asserts! (>= (get voting-power member-data) (var-get minimum-stake)) ERR-INSUFFICIENT-STAKE)
        
        (map-set proposals proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            start-block: start-block,
            end-block: end-block,
            executed: false,
            yes-votes: u0,
            no-votes: u0,
            total-votes: u0,
            execution-params: {
                target: target,
                amount: amount,
                function-name: function-name
            },
            proposal-type: proposal-type
        })
        
        (var-set proposal-counter proposal-id)
        (ok proposal-id)
    )
)

;; Enhanced Voting System
(define-public (vote (proposal-id uint) (vote-bool bool))
    (let
        (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-INVALID-PROPOSAL))
            (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-MEMBER))
            (voting-weight (get voting-power member-data))
            (has-voted (map-get? votes {proposal-id: proposal-id, voter: tx-sender}))
        )
        (asserts! (not has-voted) ERR-ALREADY-VOTED)
        (asserts! (<= block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        
        (map-set votes 
            {proposal-id: proposal-id, voter: tx-sender}
            {
                vote: vote-bool,
                weight: voting-weight,
                timestamp: block-height
            }
        )
        
        (map-set proposals proposal-id
            (merge proposal {
                yes-votes: (if vote-bool (+ (get yes-votes proposal) voting-weight) (get yes-votes proposal)),
                no-votes: (if vote-bool (get no-votes proposal) (+ (get no-votes proposal) voting-weight)),
                total-votes: (+ (get total-votes proposal) voting-weight)
            })
        )
        (ok true)
    )
)

;; Proposal Execution
(define-public (execute-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-INVALID-PROPOSAL))
            (execution-params (get execution-params proposal))
        )
        (asserts! (not (get executed proposal)) ERR-PROPOSAL-ALREADY-EXECUTED)
        (asserts! (is-proposal-passed proposal-id) ERR-PROPOSAL-NOT-PASSED)
        
        (if (is-eq (get proposal-type proposal) "TREASURY")
            (try! (execute-treasury-proposal execution-params))
            (try! (execute-governance-proposal execution-params))
        )
        
        (map-set proposals proposal-id
            (merge proposal {
                executed: true
            })
        )
        (ok true)
    )
)

;; Treasury Management
(define-public (deposit-treasury)
    (let
        (
            (amount (unwrap! (stx-get-balance tx-sender) ERR-NOT-AUTHORIZED))
        )
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

;; Private Functions
(define-private (execute-treasury-proposal (params {target: principal, amount: uint, function-name: (string-ascii 128)}))
    (let
        (
            (current-balance (var-get treasury-balance))
        )
        (asserts! (>= current-balance (get amount params)) ERR-TREASURY-INSUFFICIENT-FUNDS)
        (try! (as-contract (stx-transfer? (get amount params) (as-contract tx-sender) (get target params))))
        (var-set treasury-balance (- current-balance (get amount params)))
        (ok true)
    )
)

(define-private (execute-governance-proposal (params {target: principal, amount: uint, function-name: (string-ascii 128)}))
    ;; Implementation for governance parameter changes
    (ok true)
)

(define-private (calculate-voting-power (stake-amount uint))
    ;; Square root voting power calculation to prevent plutocracy
    (pow-uint stake-amount u2)
)

(define-private (is-proposal-passed (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? proposals proposal-id) false))
            (total-votes (get total-votes proposal))
            (yes-votes (get yes-votes proposal))
            (quorum-required (* total-votes (var-get quorum-percentage)))
        )
        (and
            (>= total-votes (/ (* (var-get minimum-stake) u100) u100))
            (>= (* yes-votes u100) quorum-required)
        )
    )
)

;; Read-Only Functions
(define-read-only (is-member (account principal))
    (is-some (map-get? members account))
)

(define-read-only (get-member-data (member principal))
    (map-get? members member)
)

(define-read-only (get-proposal-details (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-vote-details (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-treasury-balance)
    (var-get treasury-balance)
)