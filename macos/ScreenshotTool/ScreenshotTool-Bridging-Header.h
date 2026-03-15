// ScreenshotTool-Bridging-Header.h
// Imports the auto-generated C header from the Rust core library.
// Build the core library first: cd core && cargo build --release
// Then copy the generated header: cp core/screenshottool.h macos/ScreenshotTool/

#ifdef LINK_RUST_CORE
#import "screenshottool.h"
#endif
