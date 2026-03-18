const std = @import("std");

pub fn CircularArray(comptime T: type, alignment: ?std.mem.Alignment) type {
    return struct {
        items: if(alignment) |a| ([]align(a.toByteUnits()) T) else []T, //Where all of the elements go
        size: u32, //Current number of elements
        capacity: u32, //Max number of elements
        frontptr: u32, //Pointer to the front of the CircularArray
        backptr: u32, //Pointer to the back of the CircularArray

        /// Constructor that allows the specification of the capacity of the CircularArray
        /// @param gpa the allocator to create memory with
        /// @param iCapacity the desired initial capacity of the CircularArray
        /// @param almt the desired aligment of the CircularArray
        /// @return the created CircularArray
        pub fn init(gpa: std.mem.Allocator, iCapacity: u32) !CircularArray(T, alignment) {
            return CircularArray(T, alignment) {
                .items = try gpa.alignedAlloc(T, alignment, iCapacity),
                .size = 0,
                .capacity = iCapacity,
                .frontptr = 0,
                .backptr = 0
            };
        }

        /// Destructor to cleanup the memory occupied by a circular array
        /// @param gpa the allocator to use to free
        pub fn deinit(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) void {
            gpa.free(self.items);
            self.items = &[_]T{};
            self.size = 0;
            self.capacity = 0;
            self.backptr = 0;
            self.frontptr = 0;
        }

        /// Returns the element at the specified index of the CircularArray
        /// @param index the index of the element we want
        /// @return the element at the given index
        pub fn get(self: *CircularArray(T, alignment), index: u32) T {
            return self.items[(self.frontptr+index) % self.capacity];
        }

        /// Moves the pointer to the front of the CircularArray one index to the left and then adds the new value at this new position
        /// If the size of the array is >= the capacity of the array, it grows the array by a factor of 2
        /// @param val the value to add
        /// @param gpa the allocator to use if the iternal data array needs to be reallocated
        pub fn addToFront(self: *CircularArray(T, alignment), val: T, gpa: std.mem.Allocator) !void {
            if(self.size >= self.capacity) try self.grow(gpa);

            self.frontptr = (self.frontptr + self.capacity - 1) % self.capacity; //Modulo to find circular index
            self.items[self.frontptr] = val;
            self.size+=1;
        }

        /// Adds the new value at the back of the CircularArray and moves the pointer to the back of the CircularArray one index to the right
        /// If the size of the array is >= the capacity of the array, it grows the array by a factor of 2
        /// @param val the value to add
        /// @param gpa the allocator to use if the iternal data array needs to be reallocated
        pub fn addToBack(self: *CircularArray(T, alignment), val: T, gpa: std.mem.Allocator) !void {
            if(self.size >= self.capacity) try self.grow(gpa);

            self.items[self.backptr] = val;
            self.backptr = (self.backptr + 1) % self.capacity; //Modulo to find circular index
            self.size+=1;
        }

        /// Returns the value at the front of the CircularArray, setting its internal value to null and moving the pointer to the front
        /// of the array one index to the right.
        /// Throws an error  when called on an empty CircularArray
        /// If the new size of the array is a quarter of the capacity, shrinks its size by half
        /// @param gpa the allocator to use if the iternal data array needs to be reallocated
        /// @return the element at the front of the CircularArray
        pub fn removeFromFront(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !T {
            if(self.size == 0)
                return error.Range;

            const res: T =  self.items[self.frontptr]; //Store desired value
            // if(@typeInfo(T) == .Pointer) self.items[self.frontptr] = null; //Set to null to ensure it cannot be used again
            self.frontptr = (self.frontptr + 1) % self.capacity;
            self.size-=1;

            //Shrink when capacity too small
            if(self.size < self.capacity / 4) {
                try self.shrink(gpa);
            }

            return res;
        }

        /// Moves the pointer to the front of the array one index to the left. Returns the value at the pointer to the back of the CircularArray,
        /// setting its internal value to null
        /// Throws an error  when called on an empty CircularArray
        /// If the new size of the array is a quarter of the capacity, shrinks its size by half
        /// @param gpa the allocator to use if the iternal data array needs to be reallocated
        /// @return the element at the back of the CircularArray
        pub fn removeFromBack(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !T {
            if(self.size == 0)
                return error.Range;

            self.backptr = (self.backptr + self.capacity - 1) % self.capacity;
            const res: T =  self.items[self.backptr]; //Store desired value
            // if(@typeInfo(T) == .Pointer) self.items[self.frontptr] = null; //Set to null to ensure it cannot be used again
            self.size-=1;

            //Shrink when capacity too small
            if(self.size < self.capacity / 4) {
                try self.shrink(gpa);
            }

            return res;
        }

        /// Clears all of the elements in the CircularArray
        /// @param gpa the allocator to use to free and reallocate the memory
        pub fn clear(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !void {
            gpa.free(self.items);
            self.items = try gpa.alignedAlloc(T, alignment, self.capacity);
            self.size = 0;
            self.frontptr = 0;
            self.backptr = 0;
        }

        /// Internal method to grow the size of the array by a factor of two
        /// Copies all elements from the old buffer into the new buffer in sorted order
        /// @param gpa the allocator to use to free and reallocate the memory
        fn grow(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !void {
            const new_capacity = if(self.capacity > 0) self.capacity * 2 else 1;
            var new_items: []T = try gpa.alignedAlloc(T, alignment, new_capacity);

            //Making sure that we copy the elements over so that the order is correct relative to the size of the new array
            for(0..self.size) |i| {
                const index = (self.frontptr + i) % self.capacity;
                new_items[i] = self.items[index];
            }

            //Resetting size and pointer values
            gpa.free(self.items);
            self.items = new_items;
            self.capacity = new_capacity;
            self.frontptr = 0;
            self.backptr = self.size;
        }

        /// Internal method to shrink the size of the array by a factor of two
        /// Copies all elements from the old buffer into the new buffer in sorted order
        /// @param gpa the allocator to use to free and reallocate the memory
        fn shrink(self: *CircularArray(T, alignment), gpa: std.mem.Allocator) !void {
            const new_capacity = if(self.capacity > 1 ) self.capacity / 2 else 1;
            var new_items: []T = try gpa.alignedAlloc(T, alignment, self.capacity);

            //Making sure that we copy the elements over so that the order is correct relative to the size of the new array
            for(0..self.size) |i| {
                const index = (self.frontptr + i) % self.capacity;
                new_items[i] = self.items[index];
            }

            //Resetting size and pointer values
            gpa.free(self.items);
            self.items= new_items;
            self.capacity = new_capacity;
            self.frontptr = 0;
            self.backptr = self.size;
        }
    };

}
