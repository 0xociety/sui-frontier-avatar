module xociety_nft::xociety_frontier;

use multisig::multisig;
use sui::display;
use sui::event;
use sui::package;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

const EAttributeLengthMismatch: u64 = 1; /// Error when attribute keys and values have different lengths
const EContractPaused: u64 = 2; /// Error when the contract is paused
const EDuplicateTokenId: u64 = 3; /// Error when token_id already exists
const ENotMultiSigSender: u64 = 4; /// Error when sender is not the registered multisig address
const EMultiSigNotConfigured: u64 = 5; /// Error when multisig is not configured

public struct XOCIETY_FRONTIER has drop {}

// --- Config ---
public struct Config has key {
  id: UID,
  is_paused: bool,
  minted_token_ids: Table<u64, bool>,
  // MultiSig fields
  multisig_pks: vector<vector<u8>>,
  multisig_weights: vector<u8>,
  multisig_threshold: u16,
  multisig_configured: bool,
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
  cap_type: std::string::String, // "AdminCap"
  action: std::string::String, // "created", "removed"
  cap_id: ID,
  actor: address, // creator or remover
  recipient: option::Option<address>, // recipient on creation
}

/// NFT metadata update event
public struct NftUpdated has copy, drop {
  nft_id: ID,
  token_id: u64,
  updater: address,
  old_name: std::string::String,
  new_name: std::string::String,
  old_description: std::string::String,
  new_description: std::string::String,
  old_image_url: std::string::String,
  new_image_url: std::string::String,
}

/// Contract pause state change event
public struct PauseStateChanged has copy, drop {
  is_paused: bool,
  actor: address,
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
    minted_token_ids: table::new(ctx),
    multisig_pks: vector::empty(),
    multisig_weights: vector::empty(),
    multisig_threshold: 0,
    multisig_configured: false,
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
  token_id: u64, // Add token_id parameter
  name: std::string::String,
  description: std::string::String,
  url: std::string::String,
  attribute_keys: vector<std::string::String>,
  attribute_values: vector<std::string::String>,
  recipient: address,
  ctx: &mut TxContext,
) {
  verify_multisig_sender(config, ctx);

  assert!(!config.is_paused, EContractPaused);
  assert!(
    vector::length(&attribute_keys) == vector::length(&attribute_values),
    EAttributeLengthMismatch,
  );

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
    attributes: attributes,
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
  ctx: &TxContext,
) {
  verify_multisig_sender(config, ctx);

  assert!(!config.is_paused, EContractPaused);
  assert!(
    vector::length(&new_attribute_keys) == vector::length(&new_attribute_values),
    EAttributeLengthMismatch,
  );

  // Store old values for event
  let old_name = nft.name;
  let old_description = nft.description;
  let old_image_url = nft.image_url;

  // Update NFT
  nft.name = new_name;
  nft.description = new_description;
  nft.image_url = new_image_url;
  nft.attributes = vec_map::from_keys_values(new_attribute_keys, new_attribute_values);

  event::emit(NftUpdated {
    nft_id: object::id(nft),
    token_id: nft.token_id,
    updater: tx_context::sender(ctx),
    old_name,
    new_name,
    old_description,
    new_description,
    old_image_url,
    new_image_url,
  });
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
public fun pause(config: &mut Config, _cap: &AdminCap, ctx: &TxContext) {
  verify_multisig_sender(config, ctx);

  config.is_paused = true;

  event::emit(PauseStateChanged {
    is_paused: true,
    actor: tx_context::sender(ctx),
  });
}

public fun unpause(config: &mut Config, _cap: &AdminCap, ctx: &TxContext) {
  verify_multisig_sender(config, ctx);

  config.is_paused = false;

  event::emit(PauseStateChanged {
    is_paused: false,
    actor: tx_context::sender(ctx),
  });
}

// --- MultiSig Functions ---
/// Transfer AdminCap to another address (e.g., multisig address)
public fun transfer_admin_cap(cap: AdminCap, recipient: address) {
  transfer::transfer(cap, recipient);
}

/// Verify that the sender is the registered multisig address
fun verify_multisig_sender(config: &Config, ctx: &TxContext) {
  assert!(config.multisig_configured, EMultiSigNotConfigured);

  let expected = multisig::derive_multisig_address_quiet(
    config.multisig_pks,
    config.multisig_weights,
    config.multisig_threshold,
  );

  assert!(ctx.sender() == expected, ENotMultiSigSender);
}

/// Configure multisig settings
public fun set_multisig_config(
  config: &mut Config,
  _cap: &AdminCap,
  pks: vector<vector<u8>>,
  weights: vector<u8>,
  threshold: u16,
  ctx: &TxContext,
) {
  // If multisig is already configured, require multisig verification to change it
  if (config.multisig_configured) {
    verify_multisig_sender(config, ctx);
  };

  config.multisig_pks = pks;
  config.multisig_weights = weights;
  config.multisig_threshold = threshold;
  config.multisig_configured = true;
}

/// Get the derived multisig address
public fun get_multisig_address(config: &Config): address {
  assert!(config.multisig_configured, EMultiSigNotConfigured);
  multisig::derive_multisig_address_quiet(
    config.multisig_pks,
    config.multisig_weights,
    config.multisig_threshold,
  )
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

#[test_only]
public fun is_multisig_configured(config: &Config): bool {
  config.multisig_configured
}

#[test_only]
public fun transfer_admin_cap_for_testing(cap: AdminCap, recipient: address) {
  transfer::transfer(cap, recipient);
}
