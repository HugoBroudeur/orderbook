pub const Asset = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Asset) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Asset) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Asset {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const Batcher = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Batcher) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Batcher) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Batcher {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const Buffer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Buffer) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Buffer) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Buffer {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const GPU = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: GPU) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: GPU) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) GPU {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const Pass = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Pass) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Pass) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Pass {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const Renderer2D = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Renderer2D) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Renderer2D) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Renderer2D {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const Sampler = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Sampler) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Sampler) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Sampler {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const Shader = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Shader) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Shader) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Shader {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
pub const Pipeline = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        example: *const fn (*anyopaque) anyerror!void,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn example(self: Asset) !void {
        return self.vtable.example(self.ptr);
    }

    pub fn deinit(self: Asset) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn interface(ptr: anytype) Asset {
        const T = @TypeOf(ptr);
        const ptr_info = @typeInfo(T);
        const Impl = struct {
            fn example(impl: *anyopaque) !void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.example(self);
            }
            fn deinit(impl: *anyopaque) void {
                const self: T = @ptrCast(@alignCast(impl));
                return ptr_info.pointer.child.deinit(self);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = &.{
                .example = Impl.example,
                .deinit = Impl.deinit,
            },
        };
    }
};
