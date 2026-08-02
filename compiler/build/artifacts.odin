package build

import "core:fmt"
import "core:os"

import "compiler:toolchain"

// build cache goes to ~/.moo/
cache_directory :: proc() -> (string, bool) {
    home, err := os.user_home_dir(context.temp_allocator)
    if err != nil {
        return "", false
    }
    cache_dir, join_err := os.join_path({home, ".moo"}, context.temp_allocator)
    if join_err != nil {
        return "", false
    }
    return cache_dir, true
}

// this helps in figuring out a unique enough path for each binary
artifact_path :: proc(source_path: string, source_hash: u64, suffix: string) -> (string, string, bool) {
    cache_dir, path_ok := cache_directory()
    if !path_ok {
        return "", "could not find the user cache directory", false
    }
    if err := os.make_directory_all(cache_dir); err != nil && err != .Exist {
        return "", fmt.aprintf("could not create cache directory: %v", err), false
    }

    name := fmt.aprintf("%s-%x%s", os.stem(source_path), source_hash, suffix)
    path, err := os.join_path({cache_dir, name}, context.temp_allocator)
    if err != nil {
        return "", fmt.aprintf("could not join cache path: %v", err), false
    }
    return path, "", true
}


// clean is used to clean up old artifacts left in cache directory
clean :: proc() -> (string, string, bool) {
    cache_dir, path_ok := cache_directory()
    if !path_ok {
        return "", "could not find the user cache directory", false
    }
    if !os.exists(cache_dir) {
        return cache_dir, "", true
    }

    entries, err := os.read_all_directory_by_path(cache_dir, context.temp_allocator)
    if err != nil {
        return cache_dir, fmt.aprintf("could not read cache: %v", err), false
    }
    for entry in entries {
        if entry.type == .Directory {
            if err := os.remove_all(entry.fullpath); err != nil {
                return cache_dir, fmt.aprintf("could not remove cache entry: %v", err), false
            }
        } else {
            if err := os.remove(entry.fullpath); err != nil {
                return cache_dir, fmt.aprintf("could not remove cache entry: %v", err), false
            }
        }
    }
    return cache_dir, "", true
}


// publish means to copy the binary from cache directory to current directory
publish :: proc(result: Build_Result, source_path: string) -> (string, string, bool) {
    destination, path_ok := toolchain.output_path(source_path)
    if !path_ok {
        return "", "could not choose a publish path", false
    }

    if err := os.copy_file(destination, result.executable); err != nil {
        return "", fmt.aprintf("could not copy executable: %v", err), false
    }
    return destination, "", true
}

