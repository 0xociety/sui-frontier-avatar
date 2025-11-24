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
const ENotPendingOwner: u64 = 6; /// Error when sender is not the pending owner
const ENoPendingOwner: u64 = 7; /// Error when there is no pending owner to accept
const EInvalidRecipient: u64 = 8; /// Error when recipient address is invalid (e.g., @0x0 or sender)
const EPendingAdminNotAccepted: u64 = 9; /// Error when pending admin has not accepted the transfer yet
const EEmptyMultisigVectors: u64 = 10; /// Error when multisig vectors are empty
const EMultisigVectorLengthMismatch: u64 = 11; /// Error when pks and weights vectors have different lengths
const EInvalidThreshold: u64 = 12; /// Error when threshold is 0 or exceeds total weights
const ETooManySigners: u64 = 13; /// Error when number of signers exceeds maximum (10)
const EInvalidPublicKeyLength: u64 = 14; /// Error when public key has invalid length
const MAX_SIGNER_IN_MULTISIG: u64 = 10; // Multisig constants
const ED25519_PUBLIC_KEY_LENGTH: u64 = 32; // flag 0x00
const SECP256K1_PUBLIC_KEY_LENGTH: u64 = 33; // flag 0x01 (compressed)
const SECP256R1_PUBLIC_KEY_LENGTH: u64 = 33; // flag 0x02 (compressed)

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
  // AdminCap ownership transfer (3-step pattern for security)
  pending_admin: option::Option<address>,
  pending_admin_accepted: bool,
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
  action: std::string::String, // "created", "removed", "transfer_initiated", etc.
  cap_id: ID,
  actor: address, // creator or remover
  recipient: option::Option<address>, // recipient on creation
}

/// Multisig configuration event
public struct MultisigConfigChanged has copy, drop {
  num_signers: u64,
  threshold: u16,
  actor: address,
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
    pending_admin: option::none(),
    pending_admin_accepted: false,
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

// --- AdminCap Ownership Transfer ---
/// Step 1: Begin AdminCap transfer by setting pending admin
/// The current owner initiates the transfer to a new address
public fun transfer_admin_cap_begin(
  config: &mut Config,
  _cap: &AdminCap,
  new_owner: address,
  ctx: &TxContext,
) {
  // Validate new owner address
  assert!(new_owner != @0x0, EInvalidRecipient);
  assert!(new_owner != ctx.sender(), EInvalidRecipient);

  config.pending_admin = option::some(new_owner);
  config.pending_admin_accepted = false;

  event::emit(CapEvent {
    cap_type: std::string::utf8(b"AdminCap"),
    action: std::string::utf8(b"transfer_initiated"),
    cap_id: object::id(_cap),
    actor: ctx.sender(),
    recipient: option::some(new_owner),
  });
}

/// Step 2: Accept AdminCap transfer
/// The pending admin must call this to confirm they want to accept ownership
public fun accept_admin_cap(config: &mut Config, ctx: &TxContext) {
  assert!(option::is_some(&config.pending_admin), ENoPendingOwner);

  let pending = *option::borrow(&config.pending_admin);
  assert!(pending == ctx.sender(), ENotPendingOwner);

  // Mark as accepted
  config.pending_admin_accepted = true;

  event::emit(CapEvent {
    cap_type: std::string::utf8(b"AdminCap"),
    action: std::string::utf8(b"transfer_accepted"),
    cap_id: object::id_from_address(@0x0), // No specific cap ID at this stage
    actor: ctx.sender(),
    recipient: option::some(ctx.sender()),
  });
}

/// Step 3: Execute AdminCap transfer
/// The current owner calls this after the pending admin has accepted
/// This completes the transfer by sending AdminCap to the new owner
public fun accept_admin_cap_execute(config: &mut Config, cap: AdminCap, ctx: &TxContext) {
  assert!(option::is_some(&config.pending_admin), ENoPendingOwner);
  assert!(config.pending_admin_accepted == true, EPendingAdminNotAccepted);

  let new_owner = *option::borrow(&config.pending_admin);

  // Reset state
  config.pending_admin = option::none();
  config.pending_admin_accepted = false;

  event::emit(CapEvent {
    cap_type: std::string::utf8(b"AdminCap"),
    action: std::string::utf8(b"transfer_completed"),
    cap_id: object::id(&cap),
    actor: ctx.sender(),
    recipient: option::some(new_owner),
  });

  // Transfer AdminCap to the new owner
  transfer::transfer(cap, new_owner);
}

/// Renounce pending AdminCap transfer
/// The current owner can cancel the pending transfer at any time
public fun renounce_admin_cap_transfer(config: &mut Config, _cap: &AdminCap, ctx: &TxContext) {
  assert!(option::is_some(&config.pending_admin), ENoPendingOwner);

  let cancelled_recipient = *option::borrow(&config.pending_admin);

  // Reset state
  config.pending_admin = option::none();
  config.pending_admin_accepted = false;

  event::emit(CapEvent {
    cap_type: std::string::utf8(b"AdminCap"),
    action: std::string::utf8(b"transfer_renounced"),
    cap_id: object::id(_cap),
    actor: ctx.sender(),
    recipient: option::some(cancelled_recipient),
  });
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

  // Validate parameters to prevent DoS
  let pks_len = vector::length(&pks);
  let weights_len = vector::length(&weights);

  // Check vectors are not empty
  assert!(pks_len > 0, EEmptyMultisigVectors);
  assert!(weights_len > 0, EEmptyMultisigVectors);

  // Check maximum number of signers
  assert!(pks_len <= MAX_SIGNER_IN_MULTISIG, ETooManySigners);

  // Check vectors have same length
  assert!(pks_len == weights_len, EMultisigVectorLengthMismatch);

  // Validate each public key length
  let mut i = 0;
  while (i < pks_len) {
    let pk_len = vector::length(vector::borrow(&pks, i));
    // Valid lengths: 32 (Ed25519) or 33 (Secp256k1/Secp256r1 compressed)
    assert!(
      pk_len == ED25519_PUBLIC_KEY_LENGTH ||
                pk_len == SECP256K1_PUBLIC_KEY_LENGTH ||
                pk_len == SECP256R1_PUBLIC_KEY_LENGTH,
      EInvalidPublicKeyLength,
    );
    i = i + 1;
  };

  // Calculate total weight
  let mut total_weight: u16 = 0;
  let mut i = 0;
  while (i < weights_len) {
    total_weight = total_weight + (*vector::borrow(&weights, i) as u16);
    i = i + 1;
  };

  // Validate threshold
  assert!(threshold > 0, EInvalidThreshold);
  assert!(threshold <= total_weight, EInvalidThreshold);

  config.multisig_pks = pks;
  config.multisig_weights = weights;
  config.multisig_threshold = threshold;
  config.multisig_configured = true;

  // Emit event for transparency
  event::emit(MultisigConfigChanged {
    num_signers: pks_len,
    threshold,
    actor: ctx.sender(),
  });
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
