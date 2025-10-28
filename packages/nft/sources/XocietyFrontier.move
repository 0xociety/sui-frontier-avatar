module xociety_nft::xociety_frontier {
    use sui::display;
    use sui::package::Self;
    use sui::vec_map::{Self, VecMap};
    use sui::event;
    use sui::table::{Self, Table};


    const EAttributeLengthMismatch: u64 = 1; /// Error when attribute keys and values have different lengths
    const EContractPaused: u64 = 2; /// Error when the contract is paused
    const ELastAdminCap: u64 = 3; /// Error when attempting to remove the last AdminCap
    const EDuplicateTokenId: u64 = 4; /// Error when token_id already exists

    public struct XOCIETY_FRONTIER has drop {}


    // --- Config ---
    public struct Config has key {
        id: UID,
        is_paused: bool,
        admin_cap_count: u64,
        minted_token_ids: Table<u64, bool>,
    }


    // --- Cap ---
    public struct AdminCap has key {
        id: UID,
    }


    // --- Event ---
    /// NFT minting event
    public struct Minted has copy, drop {
        nft_id: ID,
        recipient: address,
        minter: address,
    }

    /// Cap management event
    public struct CapEvent has copy, drop {
        cap_type: std::string::String,  // "AdminCap"
        action: std::string::String,     // "created", "removed"
        cap_id: ID,
        actor: address,                  // creator or remover
        recipient: option::Option<address>,  // recipient on creation
    }


    public struct XocietyFrontier has key, store {
        id: UID,
        token_id: u64,
        name: std::string::String,
        description: std::string::String,
        image_url: std::string::String,
        attributes: VecMap<std::string::String, std::string::String>,
    }

    public struct NFTMetadata has copy, drop {
        token_id: u64,
        name: std::string::String,
        description: std::string::String,
        image_url: std::string::String,
        attributes: VecMap<std::string::String, std::string::String>,
    }

    fun init(otw: XOCIETY_FRONTIER, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        
        event::emit(CapEvent {
            cap_type: std::string::utf8(b"AdminCap"),
            action: std::string::utf8(b"created"),
            cap_id: object::id(&admin_cap),
            actor: ctx.sender(),
            recipient: option::some(ctx.sender()),
        });
        
        transfer::transfer(admin_cap, ctx.sender());

        let config = Config {
            id: object::new(ctx),
            is_paused: false,
            admin_cap_count: 1,
            minted_token_ids: table::new(ctx),
        };
        transfer::share_object(config);


        // --- Create Display object ---
        let mut display = display::new<XocietyFrontier>(&publisher, ctx);
        let keys = vector[
            std::string::utf8(b"name"),
            std::string::utf8(b"description"),
            std::string::utf8(b"image_url"),
            std::string::utf8(b"attributes"),
        ];

        let values = vector[
            std::string::utf8(b"{name}"),
            std::string::utf8(b"{description}"),
            std::string::utf8(b"{image_url}"),
            std::string::utf8(b"{attributes}"),
        ];
        display::add_multiple(&mut display, keys, values);
        display::update_version(&mut display);

        // Transfer Publisher and Display to admin
        // TransferPolicy will be created later via separate function calls
        transfer::public_transfer(publisher, ctx.sender());
        transfer::public_transfer(display, ctx.sender());
    }


    /// mint NFT
    public fun mint(
        config: &mut Config,
        _cap: &AdminCap,
        token_id: u64,  // Add token_id parameter
        name: std::string::String,
        description: std::string::String,
        url: std::string::String,
        attribute_keys: vector<std::string::String>,
        attribute_values: vector<std::string::String>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        assert!(!config.is_paused, EContractPaused);
        assert!(vector::length(&attribute_keys) == vector::length(&attribute_values), EAttributeLengthMismatch);

        // Ensure token_id is unique
        assert!(!table::contains(&config.minted_token_ids, token_id), EDuplicateTokenId);
        table::add(&mut config.minted_token_ids, token_id, true);

        let attributes = vec_map::from_keys_values(attribute_keys, attribute_values);

        let nft = XocietyFrontier {
            id: object::new(ctx),
            token_id: token_id,
            name: name,
            description: description,
            image_url: url,
            attributes: attributes
        };

        event::emit(Minted {
            nft_id: object::id(&nft),
            recipient,
            minter: tx_context::sender(ctx),
        });

        transfer::public_transfer(nft, recipient);
    }


    /// update NFT metadata
    public fun update_nft(
        config: &Config,
        _cap: &AdminCap,
        nft: &mut XocietyFrontier,
        new_name: std::string::String,
        new_description: std::string::String,
        new_image_url: std::string::String,
        new_attribute_keys: vector<std::string::String>,
        new_attribute_values: vector<std::string::String>,
    ) {
        assert!(!config.is_paused, EContractPaused);
        assert!(vector::length(&new_attribute_keys) == vector::length(&new_attribute_values), EAttributeLengthMismatch);
        
        nft.name = new_name;
        nft.description = new_description;
        nft.image_url = new_image_url;
        nft.attributes = vec_map::from_keys_values(new_attribute_keys, new_attribute_values);
    }


    /// Get NFT metadata
    public fun get_metadata(nft: &XocietyFrontier): NFTMetadata {
        NFTMetadata {
            token_id: nft.token_id,
            name: nft.name,
            description: nft.description,
            image_url: nft.image_url,
            attributes: nft.attributes,
        }
    }

    /// Get token_id of NFT
    public fun get_token_id(nft: &XocietyFrontier): u64 {
        nft.token_id
    }


    // --- Admin Functions ---
    public fun pause(config: &mut Config, _cap: &AdminCap) {
        config.is_paused = true;
    }

    public fun unpause(config: &mut Config, _cap: &AdminCap) {
        config.is_paused = false;
    }

    public fun add_admin(
        config: &mut Config,
        _cap: &AdminCap,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        let new_admin_cap = AdminCap {
            id: object::new(ctx),
        };

        config.admin_cap_count = config.admin_cap_count + 1;

        event::emit(CapEvent {
            cap_type: std::string::utf8(b"AdminCap"),
            action: std::string::utf8(b"created"),
            cap_id: object::id(&new_admin_cap),
            actor: tx_context::sender(ctx),
            recipient: option::some(new_admin),
        });

        transfer::transfer(new_admin_cap, new_admin);
    }


    public fun remove_admin(config: &mut Config, cap: AdminCap, ctx: &mut TxContext) {
        // Ensure at least one AdminCap remains
        assert!(config.admin_cap_count > 1, ELastAdminCap);

        let cap_id = object::id(&cap);
        let owner = tx_context::sender(ctx);

        config.admin_cap_count = config.admin_cap_count - 1;

        event::emit(CapEvent {
            cap_type: std::string::utf8(b"AdminCap"),
            action: std::string::utf8(b"removed"),
            cap_id,
            actor: owner,
            recipient: option::none(),
        });

        let AdminCap { id } = cap;
        object::delete(id);
    }

    // --- Test-only Functions ---
    #[test_only]
    public fun test_init(otw: XOCIETY_FRONTIER, ctx: &mut TxContext) {
        init(otw, ctx);
    }

    #[test_only]
    public fun is_paused(config: &Config): bool {
        config.is_paused
    }
}
