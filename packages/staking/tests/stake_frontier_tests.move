#[test_only]
module xociety_staking::stake_frontier_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils;
    use sui::clock::{Self, Clock};
    use std::string;

    use xociety_staking::stake_frontier::{Self, StakingPool, AdminCap, STAKE_FRONTIER};
    use xociety_nft::xociety_frontier::{Self, XocietyFrontier, Config, AdminCap as NftAdminCap, XOCIETY_FRONTIER};

    // Test addresses
    const ADMIN: address = @0xAD;
    const USER1: address = @0xA1;
    const USER2: address = @0xA2;

    // Helper function to initialize NFT module
    fun init_nft_for_test(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let otw = test_utils::create_one_time_witness<XOCIETY_FRONTIER>();
            xociety_frontier::test_init(otw, ts::ctx(scenario));
        };
    }

    // Helper function to initialize staking module
    fun init_staking_for_test(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let otw = test_utils::create_one_time_witness<STAKE_FRONTIER>();
            stake_frontier::test_init(otw, ts::ctx(scenario));
        };
    }

    // Helper function to mint an NFT
    fun mint_nft(scenario: &mut Scenario, token_id: u64, recipient: address) {
        ts::next_tx(scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<NftAdminCap>(scenario);
            let mut config = ts::take_shared<Config>(scenario);

            let keys = vector[string::utf8(b"rarity")];
            let values = vector[string::utf8(b"Common")];

            xociety_frontier::mint(
                &mut config,
                &admin_cap,
                token_id,
                string::utf8(b"Test NFT"),
                string::utf8(b"Description"),
                string::utf8(b"https://example.com/nft.png"),
                keys,
                values,
                recipient,
                ts::ctx(scenario)
            );

            ts::return_to_sender(scenario, admin_cap);
            ts::return_shared(config);
        };
    }

    #[test]
    fun test_init_creates_pool_and_admin() {
        let mut scenario = ts::begin(ADMIN);
        init_staking_for_test(&mut scenario);

        // Check AdminCap was created
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Check StakingPool was created
        ts::next_tx(&mut scenario, ADMIN);
        {
            let pool = ts::take_shared<StakingPool>(&scenario);
            assert!(!stake_frontier::is_paused(&pool), 1);
            assert!(stake_frontier::get_max_stake_per_user(&pool) == 25, 2);
            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_stake_unstake_success() {
        let mut scenario = ts::begin(ADMIN);
        init_nft_for_test(&mut scenario);
        init_staking_for_test(&mut scenario);

        // Mint NFT to USER1
        mint_nft(&mut scenario, 1001, USER1);

        // Create clock
        ts::next_tx(&mut scenario, ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000);

        // USER1 stakes the NFT
        ts::next_tx(&mut scenario, USER1);
        {
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
            let nft_id = object::id(&nft);

            stake_frontier::stake(&mut pool, vector[nft], &clock, ts::ctx(&mut scenario));

            // Verify staking
            assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 1, 0);
            let (staker, _timestamp) = stake_frontier::get_stake_info(&pool, nft_id);
            assert!(staker == USER1, 1);

            ts::return_shared(pool);
        };

        // USER1 unstakes the NFT
        ts::next_tx(&mut scenario, USER1);
        {
            let mut pool = ts::take_shared<StakingPool>(&scenario);

            // Get all staked NFTs for USER1
            let all_stakes = stake_frontier::get_all_stakes(&pool);
            let mut nft_ids = vector::empty<ID>();
            let mut i = 0;
            while (i < vector::length(&all_stakes)) {
                let stake_info = vector::borrow(&all_stakes, i);
                let (nft_id, _token_id, staker, _timestamp) = stake_frontier::get_stake_info_parts(stake_info);
                if (staker == USER1) {
                    vector::push_back(&mut nft_ids, nft_id);
                };
                i = i + 1;
            };

            stake_frontier::unstake(&mut pool, nft_ids, &clock, ts::ctx(&mut scenario));

            // Verify unstaking
            assert!(stake_frontier::get_staked_count_for_user(&pool, USER1) == 0, 2);

            ts::return_shared(pool);
        };

        // Verify USER1 has the NFT back
        ts::next_tx(&mut scenario, USER1);
        {
            assert!(ts::has_most_recent_for_sender<XocietyFrontier>(&scenario), 3);
            let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
            ts::return_to_sender(&scenario, nft);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake_frontier::ENotStaker)]
    fun test_unstake_by_non_staker_fails() {
        let mut scenario = ts::begin(ADMIN);
        init_nft_for_test(&mut scenario);
        init_staking_for_test(&mut scenario);

        // Mint NFT to USER1
        mint_nft(&mut scenario, 1001, USER1);

        // Create clock
        ts::next_tx(&mut scenario, ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000000);

        // USER1 stakes the NFT
        ts::next_tx(&mut scenario, USER1);
        let nft_id = {
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
            let id = object::id(&nft);

            stake_frontier::stake(&mut pool, vector[nft], &clock, ts::ctx(&mut scenario));

            ts::return_shared(pool);
            id
        };

        // USER2 tries to unstake USER1's NFT - should fail
        ts::next_tx(&mut scenario, USER2);
        {
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            stake_frontier::unstake(&mut pool, vector[nft_id], &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake_frontier::EStakingPaused)]
    fun test_stake_when_paused_fails() {
        let mut scenario = ts::begin(ADMIN);
        init_nft_for_test(&mut scenario);
        init_staking_for_test(&mut scenario);

        // Mint NFT to USER1
        mint_nft(&mut scenario, 1001, USER1);

        // Create clock
        ts::next_tx(&mut scenario, ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Pause the pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            stake_frontier::pause(&mut pool, &admin_cap);
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
        };

        // USER1 tries to stake - should fail
        ts::next_tx(&mut scenario, USER1);
        {
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
            stake_frontier::stake(&mut pool, vector[nft], &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake_frontier::EMaxStakeCountExceeded)]
    fun test_exceed_max_stake_fails() {
        let mut scenario = ts::begin(ADMIN);
        init_nft_for_test(&mut scenario);
        init_staking_for_test(&mut scenario);

        // Mint 26 NFTs to USER1 (max is 25)
        let mut i = 0;
        while (i < 26) {
            mint_nft(&mut scenario, 1000 + i, USER1);
            i = i + 1;
        };

        // Create clock
        ts::next_tx(&mut scenario, ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // USER1 tries to stake all 26 NFTs - should fail
        ts::next_tx(&mut scenario, USER1);
        {
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            let mut nfts = vector::empty<XocietyFrontier>();

            let mut j = 0;
            while (j < 26) {
                let nft = ts::take_from_sender<XocietyFrontier>(&scenario);
                vector::push_back(&mut nfts, nft);
                j = j + 1;
            };

            stake_frontier::stake(&mut pool, nfts, &clock, ts::ctx(&mut scenario));
            ts::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_add_admin_success() {
        let mut scenario = ts::begin(ADMIN);
        init_staking_for_test(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<StakingPool>(&scenario);

            stake_frontier::add_admin(&mut pool, &admin_cap, USER1, ts::ctx(&mut scenario));

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
        };

        // Verify USER1 received AdminCap
        ts::next_tx(&mut scenario, USER1);
        {
            assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_remove_admin_success() {
        let mut scenario = ts::begin(ADMIN);
        init_staking_for_test(&mut scenario);

        // Add second admin
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            stake_frontier::add_admin(&mut pool, &admin_cap, USER1, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(pool);
        };

        // Remove second admin
        ts::next_tx(&mut scenario, USER1);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<StakingPool>(&scenario);
            stake_frontier::remove_admin(&mut pool, admin_cap, ts::ctx(&mut scenario));
            ts::return_shared(pool);
        };

        // Verify USER1 no longer has AdminCap
        ts::next_tx(&mut scenario, USER1);
        {
            assert!(!ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake_frontier::ELastAdminCap)]
    fun test_remove_last_admin_fails() {
        let mut scenario = ts::begin(ADMIN);
        init_staking_for_test(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut pool = ts::take_shared<StakingPool>(&scenario);

            // Try to remove the only admin - should fail
            stake_frontier::remove_admin(&mut pool, admin_cap, ts::ctx(&mut scenario));

            ts::return_shared(pool);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake_frontier::ENotAdmin)]
    fun test_wrong_pool_admin_fails() {
        let mut scenario = ts::begin(ADMIN);

        // Create first pool
        init_staking_for_test(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        let admin_cap_pool1 = ts::take_from_sender<AdminCap>(&scenario);

        // Create second pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let otw = test_utils::create_one_time_witness<STAKE_FRONTIER>();
            stake_frontier::test_init(otw, ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, ADMIN);
        let admin_cap_pool2 = ts::take_from_sender<AdminCap>(&scenario);
        let mut pool2 = ts::take_shared<StakingPool>(&scenario);

        // Try to use pool1's admin cap on pool2 - should fail
        stake_frontier::add_admin(&mut pool2, &admin_cap_pool1, USER1, ts::ctx(&mut scenario));

        ts::return_to_sender(&scenario, admin_cap_pool1);
        ts::return_to_sender(&scenario, admin_cap_pool2);
        ts::return_shared(pool2);
        ts::end(scenario);
    }
}
