const ecs = @import("../ecs.zig");

//  ██████╗ ██████╗ ██████╗ ███████╗██████╗     ██████╗  ██████╗  ██████╗ ██╗  ██╗
// ██╔═══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗    ██╔══██╗██╔═══██╗██╔═══██╗██║ ██╔╝
// ██║   ██║██████╔╝██║  ██║█████╗  ██████╔╝    ██████╔╝██║   ██║██║   ██║█████╔╝
// ██║   ██║██╔══██╗██║  ██║██╔══╝  ██╔══██╗    ██╔══██╗██║   ██║██║   ██║██╔═██╗
// ╚██████╔╝██║  ██║██████╔╝███████╗██║  ██║    ██████╔╝╚██████╔╝╚██████╔╝██║  ██╗
//  ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝

pub const PlaceOrderEvent = struct {
    // asset: components.AssetTypes,
    quantity: ecs.components.OrderBook.Quantity,
    side: ecs.components.OrderBook.Side,
    price: ecs.components.OrderBook.Price,
    // mt_id: ecs.TypeId,
    mt_ptr: *ecs.components.MarketTrading,
};

pub const UnlockAssetEvent = struct {
    asset: ecs.components.AssetTypes,
};

pub const ErrorEvent = struct {
    type: ecs.EcsError,
};
