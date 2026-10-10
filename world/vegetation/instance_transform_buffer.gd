extends RefCounted # Packs instance data on the CPU before one bulk rendering upload.
class_name InstanceTransformBuffer # Shares the documented MultiMesh layout between vegetation systems.

static func pack(transforms: Array, colours: Array[Color] = []) -> PackedFloat32Array: # Produces the complete row-major transform and optional colour buffer.
    var stride: int = 12 if colours.is_empty() else 16 # Select the layout matching the caller's MultiMesh flags.
    var buffer: PackedFloat32Array = PackedFloat32Array() # Allocate detached upload data.
    buffer.resize(transforms.size() * stride) # Reserve exactly the required instance capacity.
    for index: int in range(transforms.size()): # Pack each transform without rendering-server calls.
        var transform: Transform3D = transforms[index] # Read the chunk-local transform.
        var offset: int = index * stride # Locate this instance's contiguous record.
        buffer[offset] = transform.basis.x.x # Write the first basis row.
        buffer[offset + 1] = transform.basis.y.x # Write the first row's second basis component.
        buffer[offset + 2] = transform.basis.z.x # Write the first row's final basis component.
        buffer[offset + 3] = transform.origin.x # Append the horizontal translation.
        buffer[offset + 4] = transform.basis.x.y # Write the second basis row.
        buffer[offset + 5] = transform.basis.y.y # Write the second row's second basis component.
        buffer[offset + 6] = transform.basis.z.y # Write the second row's final basis component.
        buffer[offset + 7] = transform.origin.y # Append the vertical translation.
        buffer[offset + 8] = transform.basis.x.z # Write the final basis row.
        buffer[offset + 9] = transform.basis.y.z # Write the final row's second basis component.
        buffer[offset + 10] = transform.basis.z.z # Write the final row's final basis component.
        buffer[offset + 11] = transform.origin.z # Append the depth translation.
        if stride == 16: # Include colours only for batches configured to use them.
            buffer[offset + 12] = colours[index].r # Store the red component.
            buffer[offset + 13] = colours[index].g # Store the green component.
            buffer[offset + 14] = colours[index].b # Store the blue component.
            buffer[offset + 15] = colours[index].a # Store the opacity component.
    return buffer # Return a complete buffer for a single upload.
