const components = @import("components.zig");
const ecs = @import("ecs");

//  ██████╗ ██████╗ ██████╗ ███████╗██████╗     ██████╗  ██████╗  ██████╗ ██╗  ██╗
// ██╔═══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗    ██╔══██╗██╔═══██╗██╔═══██╗██║ ██╔╝
// ██║   ██║██████╔╝██║  ██║█████╗  ██████╔╝    ██████╔╝██║   ██║██║   ██║█████╔╝
// ██║   ██║██╔══██╗██║  ██║██╔══╝  ██╔══██╗    ██╔══██╗██║   ██║██║   ██║██╔═██╗
// ╚██████╔╝██║  ██║██████╔╝███████╗██║  ██║    ██████╔╝╚██████╔╝╚██████╔╝██║  ██╗
//  ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝

pub const PlaceOrderEvent = struct {
    id: ecs.zflecs.entity_t,
    asset: components.MetalTypes,
    quantity: components.OrderBook.Quantity,
    side: components.OrderBook.Side,
    price: components.OrderBook.Price,
};

pub const UnlockResourceEvent = struct {
    id: ecs.zflecs.entity_t,
    asset: components.MetalTypes,
};

pub const ErrorEvent = struct {
    id: ecs.zflecs.entity_t,
    type: ecs.EcsError,
};
