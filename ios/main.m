#import <Foundation/Foundation.h>
#include <stdlib.h>

// Winit owns UIApplicationMain on iOS. The Rust static library exposes this entry point
// and creates the window from ApplicationHandler::resumed.
extern void start_winit_app(void);

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        // Content must be in the writable container, never beside the signed executable.
        // Documents is exposed through Files/Finder by Info.plist's file sharing keys.
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *content = [documents stringByAppendingPathComponent:@"Content"];
        [[NSFileManager defaultManager] createDirectoryAtPath:content withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("OMSI_CONTENT", content.fileSystemRepresentation, 1);
        NSString *root = [documents stringByAppendingPathComponent:@"OMSI 2"];
        BOOL isDirectory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDirectory] && isDirectory) {
            setenv("OMSI_ROOT", root.fileSystemRepresentation, 1);
        }
        start_winit_app();
    }
    return 0;
}
