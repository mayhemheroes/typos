#![no_main]
use libfuzzer_sys::fuzz_target;

//fuzz_target!(|data: (bool, &[u8])| {
fuzz_target!(|data: &[u8]| {
    //let (unicode, source) = data;
    let source = data;
    let t = typos::tokens::TokenizerBuilder::new()
        .unicode(false)
        .build();

    for _ in t.parse_bytes(source) {}

    if let Ok(source) = std::str::from_utf8(source) {
        for _ in t.parse_str(source) {}
    }
});
