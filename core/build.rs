fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    if let Ok(config) = cbindgen::Config::from_file("cbindgen.toml") {
        if let Ok(bindings) = cbindgen::Builder::new()
            .with_crate(&crate_dir)
            .with_config(config)
            .generate()
        {
            bindings.write_to_file("screenshottool.h");
        }
    }
}
