# Quasiquotation for Swift in Haskell

This library will eventually provide quasiquotation support for Swift in
Template Haskell.

## Warning

The current project targets Swift 2.1. Unfortunately, the grammar is
quite left-recursive — not just on a small scale but on a large scale.
The left-recursion was not something I noticed until I was well into the
implementation. It looks as though the changes for Swift 3 might help in
this regard, though I haven't checked the grammar carefully. Of course,
now there's Swift 5 😅.

A [grammar checker][grammar-checker]/generator may be useful to forewarn
the use of parser combinators.

If possible, perhaps it would be better to reuse the Swift parser.

## Resources

- [Swift 5.1 Grammar Summary][swift-grammar]
- [Swift Syntax and Structured Editing Library][swift-syntax-lib]

## TODO

- [ ] Upgrade to Swift 5 🤣.
- [ ] Fix "large scale" left-recursion.
- [ ] remaining `pattern` productions.
- [ ] Replace interim `identifier` parser with one that meets the spec.
- [ ] `getter-setter-keyword-block` (currently disguised as simply
      `getter-setter-block`).
- [ ] expressions need to use `chainr` and `chainl`.
- [ ] missing/incomplete rendering functions.
- [ ] additional test cases:
  - [ ] closures and closure signatures
  - [ ] availability conditions
  - [ ] protocol members
  - [ ] nested expressions
  - [ ] enums

[grammar-checker]: http://smlweb.cpsc.ucalgary.ca/start.html
[swift-grammar]: https://docs.swift.org/swift-book/ReferenceManual/zzSummaryOfTheGrammar.html
[swift-syntax-lib]: https://github.com/apple/swift/tree/master/lib/Syntax
