[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  locals_without_parens: [
    assert_style: 1,
    assert_style: 2
  ],
  plugins: [Styler],
  styler: [alias_lifting_exclude: []],
  line_length: 122
]
