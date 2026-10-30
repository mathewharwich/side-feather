use pipl::*;

fn main() {
    println!("cargo:rerun-if-changed=src/FeatherCore.h");
    println!("cargo:rerun-if-changed=src/FeatherBridge.cpp");
    println!("cargo:rustc-cfg=catch_panics");
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .flag_if_supported("-fno-exceptions")
        .flag_if_supported("-fno-rtti")
        .file("src/FeatherBridge.cpp")
        .compile("feather_core");

    plugin_build(vec![
        Property::Kind(PIPLType::AEEffect),
        Property::Name("Side Feather"),
        Property::Category("Harwich"),
        Property::CodeMacIntel64("EffectMain"),
        Property::CodeMacARM64("EffectMain"),
        Property::AE_PiPL_Version { major: 2, minor: 0 },
        Property::AE_Effect_Spec_Version { major: 13, minor: 28 },
        Property::AE_Effect_Version {
            version: 0, subversion: 1, bugversion: 0,
            stage: Stage::Develop, build: 3,
        },
        Property::AE_Effect_Info_Flags(0),
        Property::AE_Effect_Global_OutFlags(OutFlags::PixIndependent | OutFlags::DeepColorAware),
        // The v0.4 Rust entry-point wrapper borrows mutable global state.
        // Do not advertise multiframe concurrency until the wrapper is upgraded.
        Property::AE_Effect_Global_OutFlags_2(OutFlags2::empty()),
        Property::AE_Effect_Match_Name("com.mathewharwich.EdgeFeather"),
        Property::AE_Reserved_Info(0),
        Property::AE_Effect_Support_URL("https://github.com/mathewharwich/side-feather/issues"),
    ]);
}
