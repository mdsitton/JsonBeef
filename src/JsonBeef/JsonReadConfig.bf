using System;

namespace JsonBeef;

/// @brief Settings for reading JSON: the dialect, the source name for errors, and resource limits for
/// untrusted input. The defaults read RFC 8259 JSON exactly (with a leading byte order mark skipped)
/// and limit only the nesting depth.
public struct JsonReadConfig
{
	/// @brief Name of the input for error messages, typically its file path. Only viewed: it must
	/// outlive the read.
	public StringView SourceName = default;

	/// @brief Skip one leading UTF-8 byte order mark (RFC 8259 §8.1 lets parsers ignore it). Off: a BOM
	/// is an error.
	public bool AllowBom = true;

	/// @brief Maximum nesting depth of arrays and objects: 1 allows `[1]` but not `[[1]]`. 0 =
	/// unlimited (the reader is iterative: depth costs one bit per level).
	public int MaxDepth = 1024;
	/// @brief Maximum input size in bytes. 0 = unlimited.
	public int MaxInputBytes = 0;
	/// @brief Maximum length in bytes of a string or member name after unescaping. 0 = unlimited.
	public int MaxStringBytes = 0;
	/// @brief Maximum length in bytes of a number token. 0 = unlimited (conversions are bounded anyway).
	public int MaxNumberLength = 0;

	/// @brief Buffer size in bytes for reading a Stream. 0 = default (64 KiB); values below 16 are raised
	/// to 16 (`JsonTester -stream 1` reads through the smallest buffer).
	public int StreamBufferBytes = 0;
	/// @brief Streams only: the most bytes the reader may hold at once for one token (a string, number
	/// or literal), counted from its start through the byte after it. Longer tokens fail with
	/// ResourceLimitExceeded whatever the buffer size. 0 = unlimited (bounded by MaxInputBytes and
	/// MaxStringBytes).
	public int MaxTokenBytes = 0;

	/// @brief The defaults: RFC 8259, a leading BOM skipped, MaxDepth 1024.
	public static Self Default => .();

	/// @brief Finite limits for input from untrusted sources: depth 128, 64 MiB of input, 16 MiB strings
	/// and 4,096-byte numbers.
	public static Self Untrusted
	{
		get
		{
			Self config = .();
			config.MaxDepth = 128;
			config.MaxInputBytes = 64 * 1024 * 1024;
			config.MaxStringBytes = 16 * 1024 * 1024;
			config.MaxNumberLength = 4096;
			return config;
		}
	}
}
