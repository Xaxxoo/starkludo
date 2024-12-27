#[cfg(test)]
mod tests {
    use dojo_cairo_test::WorldStorageTestTrait;
    use dojo::model::{ModelStorage, ModelValueStorage, ModelStorageTest};
    use dojo::world::WorldStorageTrait;
    use dojo_cairo_test::{
        spawn_test_world, NamespaceDef, TestResource, ContractDefTrait, ContractDef
    };

    use starkludo::systems::game_actions::{
        GameActions, IGameActionsDispatcher, IGameActionsDispatcherTrait
    };
    use starkludo::models::game::{Game, m_Game};
    use starkludo::models::player::{
        Player, m_Player, AddressToUsername, UsernameToAddress, m_AddressToUsername,
        m_UsernameToAddress
    };

    use starkludo::models::game::{GameMode, GameStatus};
    use starkludo::errors::Errors;

    /// Defines the namespace configuration for the Starkludo game system
    /// Returns a NamespaceDef struct containing namespace name and associated resources
    fn namespace_def() -> NamespaceDef {
        // Creates a new NamespaceDef struct with:
        // Namespace name "starkludo"
        // Array of TestResource enums for models, contracts and events
        let ndef = NamespaceDef {
            namespace: "starkludo", resources: [
                // Register the Game model's class hash
                TestResource::Model(m_Game::TEST_CLASS_HASH),
                // Register the Player model's class hash
                TestResource::Model(m_Player::TEST_CLASS_HASH),
                TestResource::Model(m_AddressToUsername::TEST_CLASS_HASH),
                TestResource::Model(m_UsernameToAddress::TEST_CLASS_HASH),
                // Register the main contract containing game actions

                TestResource::Contract(GameActions::TEST_CLASS_HASH),
                // Register the GameCreated event's class hash
                TestResource::Event(GameActions::e_GameCreated::TEST_CLASS_HASH),
                TestResource::Event(GameActions::e_GameStarted::TEST_CLASS_HASH),
            ].span() // Convert array to a Span type
        };

        // Return the namespace definition
        ndef
    }

    /// Creates a single contract definition for the "GameActions" contract
    /// Sets up write permissions for the contract using a specific hash
    /// Returns the configuration wrapped in a Span container
    fn contract_defs() -> Span<ContractDef> {
        [
            // Create a new contract definition for the StarKLudo game's actions
            // using the ContractDefTrait builder pattern
            ContractDefTrait::new(@"starkludo", @"GameActions")
                // Configure write permissions by specifying which addresses can modify the contract
                // Here, only the address derived from hashing "starkludo" has write access
                .with_writer_of([dojo::utils::bytearray_hash(@"starkludo")].span())
        ].span() // Convert the array to a Span container for return
    }

    #[test]
    fn test_world() {
        let caller = starknet::contract_address_const::<'caller'>();

        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"GameActions").unwrap();
        let game_action_system = IGameActionsDispatcher { contract_address };
    }

    #[test]
    fn test_roll() {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"GameActions").unwrap();
        let game_action_system = IGameActionsDispatcher { contract_address };

        let mut unique_rolls = ArrayTrait::new();
        let mut i: u8 = 0;
        while i < 100 {
            let (dice1, dice2) = game_action_system.roll();

            assert(dice1 <= 6, 'Dice1 Exceeded Max');
            assert(dice1 > 0, 'Dice1 Below Min');
            assert(dice2 <= 6, 'Dice2 Exceeded Max');
            assert(dice2 > 0, 'Dice2 Below Min');

            let roll_combo = dice1 * 10 + dice2;
            unique_rolls.append(roll_combo);

            i += 1;
        };

        assert(unique_rolls.len() > 1, 'Not enough unique rolls');
    }

    #[test]
    fn test_get_username_from_address() {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"GameActions").unwrap();
        let game_action_system = IGameActionsDispatcher { contract_address };

        let test_address1 = starknet::contract_address_const::<'test_user1'>();
        let test_address2 = starknet::contract_address_const::<'test_user2'>();
        let username1: felt252 = 'alice';
        let username2: felt252 = 'bob';

        let address_to_username1 = AddressToUsername {
            address: test_address1, username: username1
        };
        let address_to_username2 = AddressToUsername {
            address: test_address2, username: username2
        };

        world.write_model(@address_to_username1);
        world.write_model(@address_to_username2);

        let retrieved_username1 = game_action_system.get_username_from_address(test_address1);
        let retrieved_username2 = game_action_system.get_username_from_address(test_address2);

        assert(retrieved_username1 == username1, 'Wrong username for address1');
        assert(retrieved_username2 == username2, 'Wrong username for address2');

        let non_existent_address = starknet::contract_address_const::<'non_existent'>();
        let retrieved_username3 = game_action_system
            .get_username_from_address(non_existent_address);
        assert(retrieved_username3 == 0, 'Non-existent should return 0');
    }

    fn test_start_game_success() {
        // Setup world and contract
        let caller = starknet::contract_address_const::<'Mr_T'>();
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"GameActions").unwrap();
        let game_action_system = IGameActionsDispatcher { contract_address };

        // Setup caller's username mapping
        let username: felt252 = 'test_player';
        let address_username = AddressToUsername { address: caller, username };
        let username_address = UsernameToAddress { username, address: caller };
        world.write_model(@address_username);
        world.write_model(@username_address);

        // Create new game
        let game_id = game_action_system
            .create(
                GameMode::MultiPlayer,
                username, // green player (creator)
                'player2',
                'player3',
                'player4',
                4
            );

        // Start game
        game_action_system.start();

        // Verify game state
        let game: Game = world.read_model(game_id);
        assert(game.game_status == GameStatus::Ongoing, 'Game should be ongoing');
        assert(game.next_player == game.player_green, 'Green should be next player');
    }

    #[test]
    fn test_get_address_from_username() {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"GameActions").unwrap();
        let game_action_system = IGameActionsDispatcher { contract_address };

        let bob_address = starknet::contract_address_const::<'bob'>();
        let alice_address = starknet::contract_address_const::<'alice'>();
        let bob_username: felt252 = 'bob';
        let alice_username: felt252 = 'alice';

        let address_to_username1 = UsernameToAddress {
            username: bob_username, address: bob_address,
        };
        let address_to_username2 = UsernameToAddress {
            username: alice_username, address: alice_address,
        };

        world.write_model(@address_to_username1);
        world.write_model(@address_to_username2);

        let address_1 = game_action_system.get_address_from_username(bob_username);
        let address_2 = game_action_system.get_address_from_username(alice_username);

        assert(address_1 == bob_address, 'Wrong address 1');
        assert(address_2 == alice_address, 'Wrong address 2');

        let non_existent_address = starknet::contract_address_const::<'non_existent'>();
        let retrieved_username3 = game_action_system
            .get_username_from_address(non_existent_address);
        assert(retrieved_username3 == 0, 'Non-existent should return 0');
    }
}
