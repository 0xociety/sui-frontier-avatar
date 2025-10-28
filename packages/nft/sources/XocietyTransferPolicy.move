module xociety_nft::xociety_transfer_policy {
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap};
    use sui::package::Publisher;

    /// Create TransferPolicy with standard Kiosk royalty rule
    public fun create_policy_with_standard_royalty<T: key + store>(
        publisher: &Publisher,
        royalty_bps: u16,
        min_amount: u64,
        ctx: &mut TxContext
    ): (TransferPolicy<T>, TransferPolicyCap<T>) {
        let (mut policy, policy_cap) = transfer_policy::new<T>(publisher, ctx);

        // standard royalty rule from Mysten Labs Kiosk package
        kiosk::royalty_rule::add<T>(
            &mut policy,
            &policy_cap,
            royalty_bps,
            min_amount
        );

        (policy, policy_cap)
    }
}
