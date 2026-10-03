%Doctor.Config{
  ignore_modules: [
    # Zigler injects a Manifest module with compile source "nofile"
    ExZarr.Codecs.ZigCodecs.Manifest,
    # Nested Mix helper; not part of the public API surface
    Mix.Tasks.Livebook.Test.LivemdExtract
  ],
  ignore_paths: [],
  min_module_doc_coverage: 40,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 50,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: true,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
