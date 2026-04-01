fn main() {
    // Export symbols on Windows via .def file
    if std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() == "windows" {
        let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        let def_path = std::path::Path::new(&manifest_dir).join("exports.def");
        if def_path.exists() {
            println!("cargo:rustc-cdylib-link-arg=/DEF:{}", def_path.display());
        }
    }

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
