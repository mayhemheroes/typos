#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let source = data;
    let t = typos::tokens::TokenizerBuilder::new().unicode(false).build();

    for _ in t.parse_bytes(source) {}

    if let Ok(source) = std::str::from_utf8(source) {
        let tu = typos::tokens::TokenizerBuilder::new().unicode(true).build();
        for _ in t.parse_str(source) {}
        for _ in tu.parse_str(source) {}
    }
});
