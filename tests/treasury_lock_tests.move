#[test_only]
module fungible_tokens::treasury_lock_tests {
    use std::option;
    use sui::test_scenario::{Self, Scenario};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::coin;
    use sui::object::{Self};
    use sui::test_utils;
    use fungible_tokens::treasury_lock::{Self, TreasuryLock, LockAdminCap, MintCap, create_and_transfer_mint_cap, new_lock, mint_balance};

    const ADMIN: address = @0xABBA;
    const USER: address = @0xB0B;

    // one time witness for the coin used in tests
    struct TREASURY_LOCK_TESTS has drop {}

    fun user_with_mint_cap_scenario(): Scenario {
        let scenario_ = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_;

        // create a currency and lock it
        test_scenario::next_tx(scenario, ADMIN);
        {
            let treasury_lock_tests = test_utils::create_one_time_witness<TREASURY_LOCK_TESTS>();
            let (treasury, metadata) = coin::create_currency(treasury_lock_tests, 0, b"", b"", b"", option::none(), test_scenario::ctx(scenario));
            transfer::public_freeze_object(metadata);
            let admin_cap = new_lock(treasury, test_scenario::ctx(scenario));
            transfer::public_transfer(
                admin_cap,
                ADMIN
            )
        };

        // create a mint capability and transfer it to user
        test_scenario::next_tx(scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<LockAdminCap<TREASURY_LOCK_TESTS>>(scenario);
            create_and_transfer_mint_cap(&admin_cap, 500, USER, test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, admin_cap);
        };
        test_scenario::next_tx(scenario, ADMIN);

        return scenario_
    }

    fun user_mint_balance(scenario: &mut Scenario, amount: u64): Balance<TREASURY_LOCK_TESTS> {
        let mint_cap = test_scenario::take_from_sender<MintCap<TREASURY_LOCK_TESTS>>(scenario);
        let lock = test_scenario::take_shared<TreasuryLock<TREASURY_LOCK_TESTS>>(scenario);

        let balance = mint_balance(
            &mut lock,
            &mut mint_cap,
            amount,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_to_sender(scenario, mint_cap);
        test_scenario::return_shared(lock);

        balance
    }


    #[test]
    fun test_user_can_mint() {
        let scenario_ = user_with_mint_cap_scenario();
        let scenario = &mut scenario_;

        // user uses its capability to mint 300 coins
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 300);
            assert!(balance::value<TREASURY_LOCK_TESTS>(&balance) == 300, 0);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };
        test_scenario::end(scenario_);
    }

    #[test]
    #[expected_failure(abort_code = treasury_lock::EMintAmountTooLarge)]
    fun test_minting_over_limit_fails() {
        let scenario_ = user_with_mint_cap_scenario();
        let scenario = &mut scenario_;

        // mint 300 coins
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 300);
            assert!(balance::value<TREASURY_LOCK_TESTS>(&balance) == 300, 0);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };

        // mint 200 more
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 200);
            assert!(balance::value<TREASURY_LOCK_TESTS>(&balance) == 200, 0);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };

        // attempt to mint amount over the epoch limit - should fail
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 1);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };
        test_scenario::end(scenario_);
    }

    #[test]
    fun test_minted_amount_resets_at_epoch_change() {
        let scenario_ = user_with_mint_cap_scenario();
        let scenario = &mut scenario_;

        // mint 300 coins
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 300);
            assert!(balance::value<TREASURY_LOCK_TESTS>(&balance) == 300, 0);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };

        // next epoch and mint 300 again
        test_scenario::next_epoch(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 300);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };
        test_scenario::end(scenario_);
    }

    #[test]
    #[expected_failure(abort_code = treasury_lock::EMintCapBanned)]
    fun test_banned_cap_cannot_mint() {
        let scenario_ = user_with_mint_cap_scenario();
        let scenario = &mut scenario_;

        // get the mint cap ID for reference
        test_scenario::next_tx(scenario, USER);
        let mint_cap = test_scenario::take_from_sender<MintCap<TREASURY_LOCK_TESTS>>(scenario);
        let mint_cap_id = object::id(&mint_cap);
        test_scenario::return_to_sender(scenario, mint_cap);


        // mint 100 coins
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 100);
            assert!(balance::value<TREASURY_LOCK_TESTS>(&balance) == 100, 0);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };

        // admin bans mint cap
        test_scenario::next_tx(scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<LockAdminCap<TREASURY_LOCK_TESTS>>(scenario);
            let lock = test_scenario::take_shared<TreasuryLock<TREASURY_LOCK_TESTS>>(scenario);

            treasury_lock::ban_mint_cap_id(
                &admin_cap,
                &mut lock,
                mint_cap_id
            );

            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(lock);
        };

        // user attempts to mint but fails
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 100);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };
        test_scenario::end(scenario_);
    }

    #[test]
    fun test_user_can_mint_after_unban() {
        let scenario_ = user_with_mint_cap_scenario();
        let scenario = &mut scenario_;

        // get the mint cap ID for reference
        test_scenario::next_tx(scenario, USER);
        let mint_cap = test_scenario::take_from_sender<MintCap<TREASURY_LOCK_TESTS>>(scenario);
        let mint_cap_id = object::id(&mint_cap);
        test_scenario::return_to_sender(scenario, mint_cap);

        // mint 100 coins
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 100);
            assert!(balance::value<TREASURY_LOCK_TESTS>(&balance) == 100, 0);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };

        // admin bans mint cap
        test_scenario::next_tx(scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<LockAdminCap<TREASURY_LOCK_TESTS>>(scenario);
            let lock = test_scenario::take_shared<TreasuryLock<TREASURY_LOCK_TESTS>>(scenario);

            treasury_lock::ban_mint_cap_id(
                &admin_cap,
                &mut lock,
                mint_cap_id
            );

            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(lock);
        };

        // admin unbans mint cap
        test_scenario::next_tx(scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<LockAdminCap<TREASURY_LOCK_TESTS>>(scenario);
            let lock = test_scenario::take_shared<TreasuryLock<TREASURY_LOCK_TESTS>>(scenario);

            treasury_lock::unban_mint_cap_id(
                &admin_cap,
                &mut lock,
                mint_cap_id
            );

            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(lock);
        };

        // user can mint
        test_scenario::next_tx(scenario, USER);
        {
            let balance = user_mint_balance(scenario, 100);
            assert!(balance::value<TREASURY_LOCK_TESTS>(&balance) == 100, 0);

            transfer::public_transfer(
                coin::from_balance(balance, test_scenario::ctx(scenario)),
                USER
            );
        };
        test_scenario::end(scenario_);
    }
}
