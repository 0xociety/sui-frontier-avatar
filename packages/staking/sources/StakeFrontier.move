module xociety_staking::stake_frontier {
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::linked_table::{Self, LinkedTable};
    use sui::event;
    use sui::dynamic_object_field as dof;

    use xociety_nft::xociety_frontier::{Self, XocietyFrontier};

    // --- Error Codes ---
    const EAlreadyStaked: u64 = 0;
    const ENotStaked: u64 = 1;
    const ENotStaker: u64 = 2;
    const EStakingPaused: u64 = 3; // Staking is paused
    const EMaxStakeCountExceeded: u64 = 4; // Exceeded maximum stake count per user
    const ENotAdmin: u64 = 5; /// Not an admin
    const EEmptyTokens: u64 = 6; // Empty vector passed as argument
    const EInputLengthMismatch: u64 = 7; // Input vectors have different lengths
    const ELastAdminCap: u64 = 8; /// Error when attempting to remove the last AdminCap

    public struct STAKE_FRONTIER has drop {}

    // Key for storing NFT as dynamic object field
    public struct NftKey has copy, drop, store {}

    public struct StakedNft has key, store {
        id: UID,
        nft_id: ID,  // Store the NFT's ID for reference
        token_id: u64,
        staker: address,
        stake_timestamp_ms: u64,
    }

    public struct StakeInfo has drop, store {
        nft_id: ID,
        token_id: u64,
        staker: address,
        stake_timestamp_ms: u64,
    }

    public struct UserStakeInfo has drop, store {
        nft_id: ID,
        token_id: u64,
        stake_timestamp_ms: u64,
    }


    // --- Cap ---
    public struct AdminCap has key, store {
        id: UID,
        pool_id: ID,
    }


    // --- Event ---
    /// NFT Stake Event
    public struct Staked has copy, drop {
        user: address,
        nft_id: ID,
        token_id: u64,
        timestamp: u64,
    }

    /// NFT UnStake Event
    public struct Unstaked has copy, drop {
        user: address,
        nft_id: ID,
        token_id: u64,
        timestamp: u64,
    }
    /// Cap management event (creation/removal)
    public struct CapEvent has copy, drop {
        cap_type: std::string::String,  // "AdminCap"
        action: std::string::String,     // "created", "removed"
        cap_id: ID,
        actor: address,                  // creator or remover
        recipient: option::Option<address>,      // recipient on creation (none on removal)
    }


    
    public struct StakingPool has key {
        id: UID,
        is_paused: bool,
        max_stake_per_user: u64,
        staked_nfts: LinkedTable<ID, StakedNft>,
        staker_to_nfts: Table<address, LinkedTable<ID, bool>>,
        staker_nft_counts: Table<address, u64>,
        admin_cap_count: u64,
    }


    fun init(_otw: STAKE_FRONTIER, ctx: &mut TxContext) {
        let pool = StakingPool {
            id: object::new(ctx),
            is_paused: false,
            max_stake_per_user: 25,
            staked_nfts: linked_table::new(ctx),
            staker_to_nfts: table::new(ctx),
            staker_nft_counts: table::new(ctx),
            admin_cap_count: 1,
        };

        let pool_id = object::id(&pool);

        let admin_cap = AdminCap {
            id: object::new(ctx),
            pool_id,
        };
        
        event::emit(CapEvent {
            cap_type: std::string::utf8(b"AdminCap"),
            action: std::string::utf8(b"created"),
            cap_id: object::id(&admin_cap),
            actor: ctx.sender(),
            recipient: option::some(ctx.sender()),
        });

        transfer::public_transfer(admin_cap, ctx.sender());
        transfer::share_object(pool);
    }


    // --- Public Functions ---
    public fun stake(
        pool: &mut StakingPool,
        mut nfts: vector<XocietyFrontier>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!pool.is_paused, EStakingPaused);
        assert!(vector::length(&nfts) > 0, EEmptyTokens);
        
        let staker = tx_context::sender(ctx);
        let timestamp = clock::timestamp_ms(clock);
        
        // Check max stake limit
        let current_count = get_user_stake_count(pool, staker);
        let new_count = current_count + vector::length(&nfts);
        assert!(new_count <= pool.max_stake_per_user, EMaxStakeCountExceeded);
        
        while (vector::length(&nfts) > 0) {
            do_stake(pool, vector::pop_back(&mut nfts), staker, timestamp, ctx);
        };
        vector::destroy_empty(nfts);
    }

    public fun unstake(pool: &mut StakingPool, nft_ids: vector<ID>, clock: &Clock, ctx: &TxContext) {
        assert!(!pool.is_paused, EStakingPaused);
        assert!(!vector::is_empty(&nft_ids), EEmptyTokens);

        let timestamp = clock::timestamp_ms(clock);
        let mut i = 0;
        while (i < vector::length(&nft_ids)) {
            do_unstake(pool, *vector::borrow(&nft_ids, i), timestamp, ctx);
            i = i + 1;
        };
    }

    // --- Internal Functions ---
    fun ensure_user_tables(pool: &mut StakingPool, staker: address, ctx: &mut TxContext) {
        if (!table::contains(&pool.staker_to_nfts, staker)) {
            table::add(&mut pool.staker_to_nfts, staker, linked_table::new<ID, bool>(ctx));
            table::add(&mut pool.staker_nft_counts, staker, 0);
        };
    }

    fun do_stake(pool: &mut StakingPool, nft: XocietyFrontier, staker: address, stake_timestamp_ms: u64, ctx: &mut TxContext) {
        let nft_id = object::id(&nft);
        assert!(!linked_table::contains(&pool.staked_nfts, nft_id), EAlreadyStaked);

        // Get token_id from NFT
        let token_id = xociety_frontier::get_token_id(&nft);

        ensure_user_tables(pool, staker, ctx);

        let user_nfts = table::borrow_mut(&mut pool.staker_to_nfts, staker);
        linked_table::push_back(user_nfts, nft_id, true);

        // Update count
        let count = table::borrow_mut(&mut pool.staker_nft_counts, staker);
        *count = *count + 1;

        // Create StakedNft object with dynamic object field for the NFT
        let mut staked_nft = StakedNft {
            id: object::new(ctx),
            nft_id,
            token_id,
            staker,
            stake_timestamp_ms,
        };

        // Store the actual NFT as a dynamic object field
        dof::add(&mut staked_nft.id, NftKey {}, nft);

        linked_table::push_back(&mut pool.staked_nfts, nft_id, staked_nft);

        event::emit(Staked {
            user: staker,
            nft_id,
            token_id,
            timestamp: stake_timestamp_ms,
        });
    }

    fun do_unstake(pool: &mut StakingPool, nft_id: ID, timestamp: u64, ctx: &TxContext) {
        assert!(linked_table::contains(&pool.staked_nfts, nft_id), ENotStaked);

        let StakedNft { mut id, nft_id: _, token_id, staker, stake_timestamp_ms: _ } = linked_table::remove(&mut pool.staked_nfts, nft_id);

        // CRITICAL SECURITY CHECK: Only the original staker can unstake
        let sender = tx_context::sender(ctx);
        assert!(staker == sender, ENotStaker);

        // Remove the NFT from the dynamic object field
        let nft: XocietyFrontier = dof::remove(&mut id, NftKey {});

        // Delete the StakedNft object
        object::delete(id);

        let user_nfts = table::borrow_mut(&mut pool.staker_to_nfts, staker);
        assert!(linked_table::contains(user_nfts, nft_id), ENotStaked);
        linked_table::remove(user_nfts, nft_id);


        let count = table::borrow_mut(&mut pool.staker_nft_counts, staker);
        *count = *count - 1;


        if (*count == 0) {
            let empty_table = table::remove(&mut pool.staker_to_nfts, staker);
            linked_table::destroy_empty(empty_table);
            table::remove(&mut pool.staker_nft_counts, staker);
        };

        transfer::public_transfer(nft, staker);

        event::emit(Unstaked {
            user: staker,
            nft_id,
            token_id,
            timestamp,
        });
    }


    // --- Admin Functions ---
    public fun admin_stake(
        pool: &mut StakingPool,
        _cap: &AdminCap,
        mut nfts: vector<XocietyFrontier>,
        mut staker_addresses: vector<address>,
        mut stake_timestamps_ms: vector<u64>,
        ctx: &mut TxContext
    ) {
        assert!(!pool.is_paused, EStakingPaused);
        let num_nfts = vector::length(&nfts);
        assert!(num_nfts > 0, EEmptyTokens);
        assert!(num_nfts == vector::length(&staker_addresses), EInputLengthMismatch);
        assert!(num_nfts == vector::length(&stake_timestamps_ms), EInputLengthMismatch);

        // Pre-validate max stake limits for all stakers - O(n) approach
        // Use a table to count NFTs per staker in this batch
        let mut staker_batch_counts = table::new<address, u64>(ctx);

        let mut i = 0;
        while (i < num_nfts) {
            let staker = *vector::borrow(&staker_addresses, i);

            if (table::contains(&staker_batch_counts, staker)) {
                let count = table::borrow_mut(&mut staker_batch_counts, staker);
                *count = *count + 1;
            } else {
                table::add(&mut staker_batch_counts, staker, 1);
            };

            i = i + 1;
        };

        // Validate each unique staker
        let mut validated_stakers = vector::empty<address>();
        let mut i = 0;
        while (i < num_nfts) {
            let staker = *vector::borrow(&staker_addresses, i);

            // Check if we already validated this staker
            if (!vector::contains(&validated_stakers, &staker)) {
                let current_count = get_user_stake_count(pool, staker);
                let batch_count = *table::borrow(&staker_batch_counts, staker);
                let new_count = current_count + batch_count;

                assert!(new_count <= pool.max_stake_per_user, EMaxStakeCountExceeded);
                vector::push_back(&mut validated_stakers, staker);
            };

            i = i + 1;
        };

        // Clean up temporary table
        table::drop(staker_batch_counts);

        while (!vector::is_empty(&nfts)) {
            let nft = vector::pop_back(&mut nfts);
            let staker = vector::pop_back(&mut staker_addresses);
            let timestamp = vector::pop_back(&mut stake_timestamps_ms);
            do_stake(pool, nft, staker, timestamp, ctx);
        };

        vector::destroy_empty(nfts);
        vector::destroy_empty(staker_addresses);
        vector::destroy_empty(stake_timestamps_ms);
    }

    public fun pause(pool: &mut StakingPool, cap: &AdminCap) {
        assert!(object::id(pool) == cap.pool_id, ENotAdmin);
        pool.is_paused = true;
    }

    public fun unpause(pool: &mut StakingPool, cap: &AdminCap) {
        assert!(object::id(pool) == cap.pool_id, ENotAdmin);
        pool.is_paused = false;
    }

    // Set maximum stake count per user
    public fun set_max_stake_per_user(pool: &mut StakingPool, cap: &AdminCap, new_count: u64) {
        assert!(object::id(pool) == cap.pool_id, ENotAdmin);
        pool.max_stake_per_user = new_count;
    }


    public fun add_admin(
        pool: &mut StakingPool,
        cap: &AdminCap,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        assert!(object::id(pool) == cap.pool_id, ENotAdmin);
        let new_admin_cap = AdminCap {
            id: object::new(ctx),
            pool_id: cap.pool_id,
        };

        pool.admin_cap_count = pool.admin_cap_count + 1;

        event::emit(CapEvent {
            cap_type: std::string::utf8(b"AdminCap"),
            action: std::string::utf8(b"created"),
            cap_id: object::id(&new_admin_cap),
            actor: tx_context::sender(ctx),
            recipient: option::some(new_admin),
        });

        transfer::public_transfer(new_admin_cap, new_admin);
    }

    public fun remove_admin(pool: &mut StakingPool, cap: AdminCap, ctx: &TxContext) {
        assert!(object::id(pool) == cap.pool_id, ENotAdmin);
        // Ensure at least one AdminCap remains
        assert!(pool.admin_cap_count > 1, ELastAdminCap);

        let cap_id = object::id(&cap);
        let actor = tx_context::sender(ctx);

        pool.admin_cap_count = pool.admin_cap_count - 1;

        event::emit(CapEvent {
            cap_type: std::string::utf8(b"AdminCap"),
            action: std::string::utf8(b"removed"),
            cap_id,
            actor,
            recipient: option::none(),
        });

        let AdminCap { id, pool_id: _ } = cap;
        object::delete(id);
    }


    // --- View Functions ---
    public fun is_paused(pool: &StakingPool): bool {
        pool.is_paused
    }

    public fun get_max_stake_per_user(pool: &StakingPool): u64 {
        pool.max_stake_per_user
    }

    public fun get_stake_info(pool: &StakingPool, nft_id: ID): (address, u64) {
        assert!(linked_table::contains(&pool.staked_nfts, nft_id), ENotStaked);
        let info = linked_table::borrow(&pool.staked_nfts, nft_id);
        (info.staker, info.stake_timestamp_ms)
    }

    fun get_user_stake_count(pool: &StakingPool, user: address): u64 {
        if (table::contains(&pool.staker_nft_counts, user)) {
            *table::borrow(&pool.staker_nft_counts, user)
        } else {
            0
        }
    }

    public fun get_staked_count_for_user(pool: &StakingPool, user: address): u64 {
        get_user_stake_count(pool, user)
    }

    public fun get_all_stakes(pool: &StakingPool): vector<StakeInfo> {
        let mut result = vector::empty<StakeInfo>();
        let mut current = linked_table::front(&pool.staked_nfts);
        while (option::is_some(current)) {
            let nft_id = *option::borrow(current);
            let info = linked_table::borrow(&pool.staked_nfts, nft_id);
            vector::push_back(&mut result, StakeInfo {
                nft_id,
                token_id: info.token_id,
                staker: info.staker,
                stake_timestamp_ms: info.stake_timestamp_ms,
            });
            current = linked_table::next(&pool.staked_nfts, nft_id);
        };
        result
    }

    public fun get_user_stakes(pool: &StakingPool, user: address): vector<UserStakeInfo> {
        let mut result = vector::empty<UserStakeInfo>();
        if (table::contains(&pool.staker_to_nfts, user)) {
            let user_nfts = table::borrow(&pool.staker_to_nfts, user);
            let mut current = linked_table::front(user_nfts);
            while (option::is_some(current)) {
                let nft_id = *option::borrow(current);
                let info = linked_table::borrow(&pool.staked_nfts, nft_id);
                vector::push_back(&mut result, UserStakeInfo {
                    nft_id,
                    token_id: info.token_id,
                    stake_timestamp_ms: info.stake_timestamp_ms,
                });
                current = linked_table::next(user_nfts, nft_id);
            };
        };
        result
    }

    // --- Test-only Functions ---
    #[test_only]
    public fun test_init(otw: STAKE_FRONTIER, ctx: &mut TxContext) {
        init(otw, ctx);
    }

    #[test_only]
    public fun get_stake_info_parts(info: &StakeInfo): (ID, u64, address, u64) {
        (info.nft_id, info.token_id, info.staker, info.stake_timestamp_ms)
    }

    #[test_only]
    public fun get_user_stake_info_parts(info: &UserStakeInfo): (ID, u64, u64) {
        (info.nft_id, info.token_id, info.stake_timestamp_ms)
    }
}