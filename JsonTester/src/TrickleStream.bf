using System;
using System.IO;

namespace JsonTester;

/// A read-only stream that hands out at most `chunk` bytes per read of another stream, so the reader's
/// refills land at every possible position (`-stream 1`: one byte at a time).
class TrickleStream : Stream
{
	Stream mInner;
	int mChunk;

	public this(Stream inner, int chunk)
	{
		mInner = inner;
		mChunk = Math.Max(chunk, 1);
	}

	public override int64 Position
	{
		get => mInner.Position;
		set => mInner.Position = value;
	}

	public override int64 Length => mInner.Length;

	public override bool CanRead => true;

	public override bool CanWrite => false;

	public override Result<int> TryRead(Span<uint8> data)
	{
		return mInner.TryRead(.(data.Ptr, Math.Min(data.Length, mChunk)));
	}

	public override Result<int> TryWrite(Span<uint8> data)
	{
		return .Err;
	}

	public override Result<void> Close()
	{
		return .Ok;
	}
}
