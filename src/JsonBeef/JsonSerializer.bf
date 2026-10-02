using System;
using System.Collections;
using System.IO;
using internal JsonBeef;

namespace JsonBeef;

/// @brief One-call reading and writing of whole JSON texts as [JsonObject] types (see
/// JsonObjectAttribute). Reading goes straight from the reader's tokens into the object, with no
/// document in between, and checks the whole text (nothing may follow the value). Use a JsonReader
/// directly to bind part of a text (`reader.Find("/data/0")`, then `obj.JsonRead(reader)`), and a
/// document node to update a document in place (`obj.JsonWrite(doc.Root)`, then `doc.WriteFile`).
///
/// ```
/// let config = scope Config();
/// Try!(JsonSerializer.ReadFile("config.json", config));
/// config.Port = 8443;
/// Try!(JsonSerializer.WriteFile(config, "config.json", .Pretty));
/// ```
public static class JsonSerializer
{
	/// @brief Parse `text` and fill `target` from its value. Errors (syntax, a value of the wrong kind,
	/// a missing required member) are located in the text, with the path of the value in error.
	/// @param text The JSON text.
	/// @param target The object to fill; fields whose members are absent keep their values.
	/// @param config Read settings (dialect, limits, DuplicateNames: FirstWins or LastWins accept a
	/// repeated member, otherwise it is an error).
	/// @param allocator Where created Strings, objects and Lists come from (for example a
	/// `scope BumpAllocator`), or null for the heap, when the object owns them.
	/// @return .Ok, or the first error.
	public static Result<void, JsonParseError> Read<T>(StringView text, T target, JsonReadConfig config = .(), ITypedAllocator allocator = null) where T : class, IJsonSerializable
	{
		let reader = scope JsonReader(text, config);
		Try!(target.JsonRead(reader, allocator));
		return End(reader);
	}

	/// @brief Parse `text` and fill the struct `target`; see the class overload.
	/// @param text The JSON text.
	/// @param target The struct to fill.
	/// @param config Read settings.
	/// @param allocator Where created objects come from, or null for the heap.
	/// @return .Ok, or the first error.
	public static Result<void, JsonParseError> Read<T>(StringView text, ref T target, JsonReadConfig config = .(), ITypedAllocator allocator = null) where T : struct, IJsonSerializable
	{
		let reader = scope JsonReader(text, config);
		Try!(target.JsonRead(reader, allocator));
		return End(reader);
	}

	/// @brief Read a stream through a buffer (JsonReadConfig.StreamBufferBytes) and fill `target`: memory
	/// stays bounded by the buffer, the longest token and the object itself.
	/// @param stream The JSON text, read from its current position.
	/// @param target The object to fill.
	/// @param config Read settings.
	/// @param allocator Where created objects come from, or null for the heap.
	/// @return .Ok, or the first error (IoError if reading fails).
	public static Result<void, JsonParseError> Read<T>(Stream stream, T target, JsonReadConfig config = .(), ITypedAllocator allocator = null) where T : class, IJsonSerializable
	{
		let reader = scope JsonReader();
		reader.Reset(stream, config);
		Try!(target.JsonRead(reader, allocator));
		return End(reader);
	}

	/// @brief Read the file at `path` and fill `target`. Errors name the file:
	/// `config.json:3:12: /server/port: Expected an integer, found the string "80"`.
	/// @param path The file to read.
	/// @param target The object to fill.
	/// @param config Read settings.
	/// @param allocator Where created objects come from, or null for the heap.
	/// @return .Ok, or the first error (IoError if the file cannot be read).
	public static Result<void, JsonParseError> ReadFile<T>(StringView path, T target, JsonReadConfig config = .(), ITypedAllocator allocator = null) where T : class, IJsonSerializable
	{
		var config;
		let text = scope String();
		Try!(LoadFile(path, ref config, text));
		let reader = scope JsonReader(text, config);
		Try!(target.JsonRead(reader, allocator));
		return End(reader);
	}

	/// @brief Read the file at `path` and fill the struct `target`.
	/// @param path The file to read.
	/// @param target The struct to fill.
	/// @param config Read settings.
	/// @param allocator Where created objects come from, or null for the heap.
	/// @return .Ok, or the first error.
	public static Result<void, JsonParseError> ReadFile<T>(StringView path, ref T target, JsonReadConfig config = .(), ITypedAllocator allocator = null) where T : struct, IJsonSerializable
	{
		var config;
		let text = scope String();
		Try!(LoadFile(path, ref config, text));
		let reader = scope JsonReader(text, config);
		Try!(target.JsonRead(reader, allocator));
		return End(reader);
	}

	/// @brief Fill `target` from a document's value: for documents read already, or edited. Errors are
	/// located at the node in error when the document has positions (JsonMetadataMode.Positions or
	/// PreserveStyle; the path says where in any case). A member repeated in the object (a KeepAll
	/// document) is an error: read the document with LastWins or FirstWins to pick one.
	///
	/// Numbers come from the source text when the document kept it, so a float field gets the float
	/// of the text; otherwise from the node's value (a float field then gets the node's double rounded
	/// to float).
	/// @param node The value (an object for a [JsonObject] type).
	/// @param target The object to fill.
	/// @param allocator Where created objects come from, or null for the heap.
	/// @return .Ok, or the first error.
	public static Result<void, JsonParseError> Read<T>(JsonNode node, T target, ITypedAllocator allocator = null) where T : class, IJsonSerializable
	{
		if (!node.IsValid)
			return .Err(JsonParseError(.InvalidStructure, "The node is not valid", 0, 0, 0, 0));
		let text = scope String();
		let spans = scope List<JsonNodeSpan>();
		JsonBind.NodeText(node, text, spans);
		let reader = scope JsonReader(text, NodeConfig());
		if (target.JsonRead(reader, allocator) case .Err(let error))
			return .Err(JsonBind.Relocate(node, spans, error));
		return .Ok;
	}

	/// @brief Fill the struct `target` from a document's value; see the class overload.
	/// @param node The value.
	/// @param target The struct to fill.
	/// @param allocator Where created objects come from, or null for the heap.
	/// @return .Ok, or the first error.
	public static Result<void, JsonParseError> Read<T>(JsonNode node, ref T target, ITypedAllocator allocator = null) where T : struct, IJsonSerializable
	{
		if (!node.IsValid)
			return .Err(JsonParseError(.InvalidStructure, "The node is not valid", 0, 0, 0, 0));
		let text = scope String();
		let spans = scope List<JsonNodeSpan>();
		JsonBind.NodeText(node, text, spans);
		let reader = scope JsonReader(text, NodeConfig());
		if (target.JsonRead(reader, allocator) case .Err(let error))
			return .Err(JsonBind.Relocate(node, spans, error));
		return .Ok;
	}

	/// @brief Write `source` as a JSON text, appending to `output`.
	/// @param source The object to write.
	/// @param output Receives the text.
	/// @param options Layout, escaping and number options (Pretty indents; Jcs gives RFC 8785 form).
	/// @return .Ok, or the first error (a NaN double with NonFiniteNumbers.Error, an enum value that is
	/// no case, a converter's).
	public static Result<void, JsonWriteError> Write<T>(T source, String output, JsonWriteOptions options = .()) where T : IJsonSerializable
	{
		if (options.Canonical)
		{
			// Canonical form sorts members: through a document
			let compact = scope String();
			let writer = scope JsonWriter(compact);
			source.JsonWrite(writer);
			Try!(writer.Finish());
			let doc = scope JsonDocument();
			if (doc.Read(compact) case .Err(let error))
				return .Err(JsonWriteError(.InvalidStructure, scope $"The written text does not read back: {error}"));
			return doc.Write(output, options);
		}
		let writer = scope JsonWriter(output, options);
		source.JsonWrite(writer);
		return writer.Finish();
	}

	/// @brief Write `source` as a new JSON text to the file at `path` (UTF-8), replacing it. To update an
	/// existing file and keep its formatting, read it into a document with PreserveStyle, JsonWrite the
	/// object into its Root, and write the document.
	/// @param source The object to write.
	/// @param path The file to write.
	/// @param options Layout, escaping and number options.
	/// @return .Ok, or the first error (IoError if the file cannot be written).
	public static Result<void, JsonWriteError> WriteFile<T>(T source, StringView path, JsonWriteOptions options = .()) where T : IJsonSerializable
	{
		let output = scope String();
		Try!(Write(source, output, options));
		if (File.WriteAllText(path, output) case .Err)
			return .Err(JsonWriteError(.IoError, scope $"Cannot write the file {path}"));
		return .Ok;
	}

	/// After the value: nothing but whitespace (and with JSONC, comments).
	static Result<void, JsonParseError> End(JsonReader reader)
	{
		let token = Try!(reader.Next());
		if (token != .EndOfDocument)
			return .Err(reader.MakeError(.InvalidStructure, "Expected the end of the input after the JSON value", reader.Offset, 1));
		return .Ok;
	}

	/// The file's text, with the path as the source name unless the config has one.
	static Result<void, JsonParseError> LoadFile(StringView path, ref JsonReadConfig config, String text)
	{
		if (config.SourceName.IsEmpty)
			config.SourceName = path;
		// The bytes as they are (no decoding: the reader checks the encoding)
		let file = scope FileStream();
		if (file.Open(path, .Read, .Read) case .Err)
			return .Err(FileError(path, .IoError, "Cannot open the file"));
		int64 length = file.Length;
		if (config.MaxInputBytes > 0 && length > config.MaxInputBytes)
			return .Err(FileError(path, .ResourceLimitExceeded, scope $"The input ({length} bytes) exceeds MaxInputBytes ({config.MaxInputBytes})"));
		char8* bytes = text.PrepareBuffer((int)length);
		int filled = 0;
		while (filled < length)
		{
			switch (file.TryRead(.((uint8*)bytes + filled, (int)length - filled)))
			{
			case .Ok(let read):
				if (read <= 0)
					return .Err(FileError(path, .IoError, "The file ended before its size"));
				filled += read;
			case .Err:
				return .Err(FileError(path, .IoError, "Reading the file failed"));
			}
		}
		return .Ok;
	}

	static JsonParseError FileError(StringView path, JsonErrorKind kind, StringView message)
	{
		var error = JsonParseError(kind, message, 0, 0, 0, 0);
		error.SetSource(path);
		return error;
	}

	/// For the text written from a node: no depth limit (the document had its own), and the non-finite
	/// numbers a document read with AllowNonFiniteNumbers may hold.
	static JsonReadConfig NodeConfig()
	{
		var config = JsonReadConfig();
		config.MaxDepth = 0;
		config.AllowNonFiniteNumbers = true;
		return config;
	}
}
