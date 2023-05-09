module fungible_tokens::treasury_lock {
    use sui::object::{Self, UID, ID};
    use sui::coin::{Self, TreasuryCap};
    use sui::balance::{Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::vec_set::{Self, VecSet};

    /// This mint capability instance is banned.
    const EMintCapBanned: u64 = 0;
    /// Requested mint amount exceeds the per epoch mint limit.
    const EMintAmountTooLarge: u64 = 1;

    /// Encapsulates the `TreasuryCap` and stores the list of banned mint authorities.
    struct TreasuryLock<phantom T> has key {
        id: UID,
        treasury_cap: TreasuryCap<T>,
        banned_mint_authorities: VecSet<ID>
    }

    /// Admin capability for `TreasuryLock`. Bearer has the power to create, ban,
    /// and unban mint capabilities (`MintCap`)
    struct LockAdminCap<phantom T> has key, store {
        id: UID
    }

    /// Capability allowing the bearer to mint new Coins up to a pre-defined per epoch limit.
    struct MintCap<phantom T> has key, store {
        id: UID,
        max_mint_per_epoch: u64,
        last_epoch: u64,
        minted_in_epoch: u64
    }

    /// Create a new `TreasuryLock` for `TreasuryCap`.
    public fun new_lock<T>(
        cap: TreasuryCap<T>, ctx: &mut TxContext
    ): LockAdminCap<T> {
        let lock = TreasuryLock {
            id: object::new(ctx),
            treasury_cap: cap,
            banned_mint_authorities: vec_set::empty<ID>()
        };
        transfer::share_object(lock);

        LockAdminCap<T> {
            id: object::new(ctx),
        }
    }

    /// Entry function. Creates a new `TreasuryLock` for `TreasuryCap`. Invokes `new_lock`.
    public entry fun new_lock_<T>(cap: TreasuryCap<T>, ctx: &mut TxContext) {
        transfer::public_transfer(
            new_lock(cap, ctx),
            tx_context::sender(ctx)
        )
    }

    /// Create a new mint capability whose bearer will be allowed to mint
    /// `max_mint_per_epoch` coins per epoch.
    public fun create_mint_cap<T>(
        _cap: &LockAdminCap<T>, max_mint_per_epoch: u64, ctx: &mut TxContext
    ): MintCap<T> {
        MintCap<T>{
            id: object::new(ctx),
            max_mint_per_epoch,
            last_epoch: tx_context::epoch(ctx),
            minted_in_epoch: 0
        }
    }

    /// Entry function. Creates a new mint capability whose bearer will be allowed
    /// to mint `max_mint_per_epoch` coins per epoch. Sends it to `recipient`.
    public fun create_and_transfer_mint_cap<T>(
        cap: &LockAdminCap<T>, max_mint_per_epoch: u64, recipient: address, ctx: &mut TxContext
    ) {
        transfer::public_transfer(
            create_mint_cap(cap, max_mint_per_epoch, ctx),
            recipient
        )
    }

    /// Ban a `MintCap`.
    public fun ban_mint_cap_id<T>(
        _cap: &LockAdminCap<T>, lock: &mut TreasuryLock<T>, id: ID
    ) {
        vec_set::insert(&mut lock.banned_mint_authorities, id)
    }

    /// Entry function. Bans a `MintCap`.
    public entry fun ban_mint_cap_id_<T>(
        cap: &LockAdminCap<T>, lock: &mut TreasuryLock<T>, id: ID
    ) {
        ban_mint_cap_id(cap, lock, id);
    }

    /// Unban a previously banned `MintCap`.
    public fun unban_mint_cap_id<T>(
        _cap: &LockAdminCap<T>, lock: &mut TreasuryLock<T>, id: ID
    ) {
        vec_set::remove(&mut lock.banned_mint_authorities, &id)
    }

    /// Entry function. Unbans a previously banned `MintCap`.
    public entry fun unban_mint_cap_id_<T>(
        cap: &LockAdminCap<T>, lock: &mut TreasuryLock<T>, id: ID
    ) {
        unban_mint_cap_id(cap, lock, id);
    }

    /// Borrow the `TreasuryCap` to use directly.
    public fun treasury_cap_mut<T>(
        _cap: &LockAdminCap<T>, lock: &mut TreasuryLock<T>
    ): &mut TreasuryCap<T> {
        &mut lock.treasury_cap
    }

    /// Mint a `Balance` from a `TreasuryLock` providing a `MintCap`.
    public fun mint_balance<T>(
        lock: &mut TreasuryLock<T>, cap: &mut MintCap<T>, amount: u64, ctx: &mut TxContext
    ): Balance<T> {
        assert!(
            !vec_set::contains(&lock.banned_mint_authorities, object::uid_as_inner(&cap.id)),
            EMintCapBanned
        );

        let epoch = tx_context::epoch(ctx);
        if (cap.last_epoch != epoch) {
            cap.last_epoch = epoch;
            cap.minted_in_epoch = 0;
        };
        assert!(
            cap.minted_in_epoch + amount <= cap.max_mint_per_epoch,
            EMintAmountTooLarge
        );

        cap.minted_in_epoch = cap.minted_in_epoch + amount;
        coin::mint_balance(&mut lock.treasury_cap, amount)
    }

    /// Entry function. Mint a `Coin` from a `TreasuryLock` providing a `MintCap`
    /// and transfer it to recipient.
    public entry fun mint_and_transfer<T>(
        lock: &mut TreasuryLock<T>,
        cap: &mut MintCap<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let balance = mint_balance(lock, cap, amount, ctx);
        transfer::public_transfer(
            coin::from_balance(balance, ctx),
            recipient
        )
    }
}
