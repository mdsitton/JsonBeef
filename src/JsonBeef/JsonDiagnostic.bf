using System;
using FormatCore;

namespace JsonBeef;

/// @brief An error that owns its text, for keeping it: a list of diagnostics, errors from several
/// readers, documents or threads. (A JsonParseError's message views a per-thread buffer that the next
/// error on the thread replaces; a document's collected errors live until it is cleared or read again.)
/// FormatCore's `Diagnostic` with JSON's error kinds: `mKind`, `mMessage`, `mSource`, `mPath` (the JSON
/// Pointer in typed binding), `mLine`, `mColumn`, `mOffset`, `mLength`, the `Error` property (a
/// JsonParseError viewing this object's text) and `ToString`. Delete it when done.
///
/// ```
/// let kept = new List<JsonDiagnostic>();
/// defer { DeleteContainerAndItems!(kept); }
/// for (let path in paths)
/// {
///     if (doc.ReadFile(path) case .Err(let error))
///         kept.Add(new JsonDiagnostic(error));
/// }
/// ```
public typealias JsonDiagnostic = FormatCore.Diagnostic<JsonErrorKind>;
