const std = @import("std");

pub fn CircularArray(comptime T: type, alignment: ?std.mem.Alignment) type {
    return struct {
        items: if(alignment) |a| ([]align(a.toByteUnits()) T) else []T,
        size: usize,
        capacity: usize,
        frontptr: u32,
        backptr: u32,


        pub fn init(gpa: std.mem.Allocator, iCapacity: usize, almt: ?std.mem.Alignment) !CircularArray(T, alignment) {
            return CircularArray(T, almt) {
                .items = try gpa.alignedAlloc(T, almt, iCapacity),
                .size = 0,
                .capacity = iCapacity,
                .frontptr = 0,
                .backptr = 0
            };
        }

        pub fn deinit(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) void {
            gpa.free(self.items);
            self.items = &[_]T{};
            self.size = 0;
            self.capacity = 0;
            self.backptr = 0;
            self.frontptr = 0;
        }

        pub fn get(self: *CircularArray(T, alignment), index: u32) T {
            return self.items[(self.frontptr+index) % self.capacity];
        }

        pub fn addToFront(self: *CircularArray(T, alignment), val: T, gpa: std.mem.Allocator) !void {
            if(self.size >= self.capacity) try self.grow(gpa);

            self.frontptr = (self.frontptr - 1 + self.capacity) % self.capacity; //Modulo to find circular index
            self.items[self.frontptr] = val;
            self.size+=1;
        }

        pub fn addToBack(self: *CircularArray(T, alignment), val: T, gpa: std.mem.Allocator) !void {
            if(self.size >= self.capacity) try self.grow(gpa);

            self.data[self.backptr] = val;
            self.backptr = (self.backptr + 1) % self.capacity; //Modulo to find circular index
            self.size+=1;
        }

        pub fn removeFromFront(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !T {
            if(self.size == 0)
                return error.Range;

            const res: T =  self.items[self.frontptr]; //Store desired value
            if(@typeInfo(T) == .Pointer) self.items[self.frontptr] = null; //Set to null to ensure it cannot be used again
            self.frontptr = (self.frontptr + 1) % self.capacity;
            self.size-=1;

            //Shrink when capacity too small
            if(self.size < self.capacity / 4) {
                try self.shrink(gpa);
            }

            return res;
        }

        pub fn removeFromBack(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !T {
            if(self.size == 0)
                return error.Range;

            self.backptr = (self.backptr - 1 + self.capacity) % self.capacity;
            const res: T =  self.items[self.backptr]; //Store desired value
            if(@typeInfo(T) == .Pointer) self.items[self.frontptr] = null; //Set to null to ensure it cannot be used again
            self.size-=1;

            //Shrink when capacity too small
            if(self.size < self.capacity / 4) {
                try self.shrink(gpa);
            }

            return res;
        }

        pub fn clear(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !void {
            self.items = try gpa.alignedAlloc(T, alignment, self.capacity);
            self.size = 0;
            self.frontptr = 0;
            self.backptr = 0;
        }

        fn grow(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !void {
            const new_capacity = if(self.capacity > 0) self.capacity * 2 else 1;
            var new_items: []T = try gpa.alignedAlloc(T, alignment, new_capacity);

            for(0..self.size) |i| {
                const index = (self.frontptr + i) % self.capacity;
                new_items[i] = self.items[index];
            }

            //Resetting size and pointer values
            self.items = new_items;
            self.capacity = new_capacity;
            self.frontptr = 0;
            self.backptr = self.size;
        }

        fn shrink(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) void {
            const new_capacity = if(self.capacity > 1 ) self.capacity / 2 else 1;
            var new_items: []T = try gpa.alignedAlloc(T, alignment, self.capacity);

            //Making sure that we copy the elements over so that the order is correct relative to the size of the new array
            for(0..self.size) |i| {
                const index = (self.frontptr + i) % self.capacity;
                new_items[i] = self.items[index];
            }

            //Resetting size and pointer values
            self.items= new_items;
            self.capacity = new_capacity;
            self.frontptr = 0;
            self.backptr = self.size;
        }
    };

}
