using System;
using System.Collections;
using internal JsonBeef;

namespace JsonBeef;

[AllowDuplicates]
internal enum JsonStyleFlags : uint8
{
	None = 0,
	/// The node's pieces were read from the source (a value added in code has none).
	Captured = 1,
	/// Regenerate the value (a scalar's text; a container's kind changed: all of it).
	ValueDirty = 2,
	/// Regenerate the member's name.
	NameDirty = 4,
	/// A container's children were added, removed or reordered.
	ChildrenDirty = 8,
	/// Something under the node changed: write it piece by piece.
	SubtreeDirty = 16,
	/// A container whose last child had a comma after it in the source (JSONC): its last child keeps one.
	TrailingComma = 32
}

/// PreserveStyle: where a node's pieces are in the source (byte offsets), in the order they are written
/// back. Between a container's children: each child's leading trivia (from the separator before it),
/// its name and the colon part, its value, its trailing trivia, its comma and the rest of the comma's
/// line (spaces and comments: an end-of-line comment belongs to the member before it).
internal struct JsonNodeStyle
{
	public int32 mLeadStart;
	/// The name (member) or the value.
	public int32 mTokenStart;
	/// Member: just after the name's closing quote (the colon part runs to mValueStart); -1 otherwise.
	public int32 mNameEnd;
	public int32 mValueStart;
	/// After the value (a container's closing bracket).
	public int32 mValueEnd;
	/// The comma after it, or -1.
	public int32 mCommaPos;
	/// After the comma's line tail; mValueEnd when there is no comma.
	public int32 mAfterEnd;
	/// Container: where the trivia before its closing bracket starts, and the bracket.
	public int32 mInnerStart;
	public int32 mCloseStart;
	/// Container: where its first child's name or value started (the text between the opening bracket
	/// and it is the layout a first child gets).
	public int32 mFirstToken;
	public JsonStyleFlags mFlags;
}

extension JsonDocument
{
	/// PreserveStyle: the document was read keeping its source; Write gives it back, regenerating only
	/// what changed.
	internal bool mPreserve;
	internal List<JsonNodeStyle> mStyles = new .() ~ delete _;
	/// The source before the root's first token (a BOM, comments) and after its value: kept when the root
	/// is replaced.
	int32 mDocLeadEnd;
	int32 mDocTrailStart;
	/// The layout of new values: one indentation level, and the text between a name and its value.
	String mIndentUnit = new .() ~ delete _;
	String mColonText = new .() ~ delete _;
	/// The source's line break (its first one: LF, CRLF or CR), for lines written new.
	String mNewLine = new .() ~ delete _;
	bool mMultiLine;

	internal ref JsonNodeStyle StyleOf(uint32 id)
	{
		while (mStyles.Count <= (int)id)
		{
			JsonNodeStyle style = default;
			style.mNameEnd = -1;
			style.mCommaPos = -1;
			mStyles.Add(style);
		}
		return ref mStyles[id];
	}

	/// Clears the style state (Clear calls it).
	void ClearStyle()
	{
		mPreserve = false;
		mStyles.Clear();
		mDocLeadEnd = 0;
		mDocTrailStart = 0;
		mIndentUnit.Clear();
		mColonText.Clear();
		mNewLine.Clear();
		mMultiLine = false;
	}

	// Capture

	/// Records a value's tokens as the builder reads it (containers: their start here, their end in
	/// CaptureEnd).
	internal void CaptureValue(uint32 id, int tokenStart, int nameEnd, int valueStart, int valueEnd)
	{
		ref JsonNodeStyle style = ref StyleOf(id);
		style.mTokenStart = (int32)tokenStart;
		style.mNameEnd = (int32)nameEnd;
		style.mValueStart = (int32)valueStart;
		style.mValueEnd = (int32)valueEnd;
		style.mFlags = .Captured;
	}

	internal void CaptureEnd(uint32 id, int closeStart, int valueEnd)
	{
		ref JsonNodeStyle style = ref StyleOf(id);
		style.mCloseStart = (int32)closeStart;
		style.mValueEnd = (int32)valueEnd;
	}

	/// After a read: the commas and trivia between the captured tokens, and the layout of new values.
	internal void FinishStyle()
	{
		mPreserve = true;
		if (mRoot == 0)
			return;
		StyleOf((uint32)mNodes.Count - 1);
		ref JsonNodeStyle root = ref mStyles[mRoot];
		root.mLeadStart = 0;
		root.mAfterEnd = root.mValueEnd;
		mDocLeadEnd = root.mTokenStart;
		mDocTrailStart = root.mValueEnd;
		// Every container's children, in preorder (records are in document order)
		for (uint32 id = 1; id < (uint32)mNodes.Count; id++)
		{
			ref JsonNodeRecord node = ref mNodes[id];
			if (!node.IsContainer || node.mFlags.HasFlag(.Removed))
				continue;
			ref JsonNodeStyle container = ref mStyles[id];
			int32 previousEnd = container.mValueStart + 1;
			uint32 child = node.mFirstChild;
			container.mFirstToken = child != 0 ? mStyles[child].mTokenStart : -1;
			while (child != 0)
			{
				ref JsonNodeStyle style = ref mStyles[child];
				style.mLeadStart = previousEnd;
				int p = SkipTrivia(style.mValueEnd, container.mCloseStart);
				if (p < container.mCloseStart && mSource[p] == ',')
				{
					style.mCommaPos = (int32)p;
					style.mAfterEnd = (int32)LineTail(p + 1, container.mCloseStart);
				}
				else
				{
					// The last child: the comments on its line are its own
					style.mCommaPos = -1;
					style.mAfterEnd = (int32)LineTail(style.mValueEnd, container.mCloseStart);
				}
				previousEnd = style.mAfterEnd;
				if (mNodes[child].mNext == 0 && style.mCommaPos >= 0)
					container.mFlags |= .TrailingComma;
				child = mNodes[child].mNext;
			}
			container.mInnerStart = previousEnd;
		}
		DetectLayout();
	}

	/// Past whitespace and comments from `p` (the source is valid: comments are well-formed).
	int SkipTrivia(int p, int end)
	{
		var p;
		while (p < end)
		{
			char8 c = mSource[p];
			if (JsonChar.IsSpace(c))
				p++;
			else if (c == '/' && p + 1 < end && mSource[p + 1] == '/')
			{
				while (p < end && mSource[p] != '\n' && mSource[p] != '\r')
					p++;
			}
			else if (c == '/' && p + 1 < end && mSource[p + 1] == '*')
			{
				p += 2;
				while (p + 1 < end && !(mSource[p] == '*' && mSource[p + 1] == '/'))
					p++;
				p += 2;
			}
			else
				break;
		}
		return Math.Min(p, end);
	}

	/// The line tail after a value (its comma, if any, before `p`): the comments on the rest of its
	/// line, and the blanks before the line break, so an end-of-line comment stays with the value. Blanks
	/// before a token on the same line belong to that token (`[1, 2]`); a block comment that runs onto
	/// the next line is not taken.
	int LineTail(int p, int end)
	{
		int taken = p;
		int q = p;
		while (true)
		{
			while (q < end && (mSource[q] == ' ' || mSource[q] == '\t'))
				q++;
			if (q >= end || mSource[q] == '\n' || mSource[q] == '\r')
				return q;
			if (mSource[q] == '/' && q + 1 < end && mSource[q + 1] == '/')
			{
				while (q < end && mSource[q] != '\n' && mSource[q] != '\r')
					q++;
				return q;
			}
			if (mSource[q] == '/' && q + 1 < end && mSource[q + 1] == '*')
			{
				int r = q + 2;
				while (r + 1 < end && !(mSource[r] == '*' && mSource[r + 1] == '/'))
				{
					if (mSource[r] == '\n' || mSource[r] == '\r')
						return taken;
					r++;
				}
				q = r + 2;
				taken = q;
				continue;
			}
			return taken;
		}
	}

	/// The indentation unit (the first child's indentation beyond its container's) and the colon text
	/// (the first member's, when it is plain whitespace and `:`), for values added later.
	void DetectLayout()
	{
		for (uint32 id = 1; id < (uint32)mNodes.Count; id++)
		{
			ref JsonNodeRecord node = ref mNodes[id];
			if (node.mParent == 0 || node.mFlags.HasFlag(.Removed))
				continue;
			let leading = LeadingOf(id);
			int newline = leading.LastIndexOf('\n');
			if (newline < 0)
				newline = leading.LastIndexOf('\r');
			if (newline >= 0 && mIndentUnit.IsEmpty)
			{
				StringView indent = leading.Substring(newline + 1);
				let parentIndent = scope String();
				IndentOf(node.mParent, parentIndent);
				if (indent.StartsWith(parentIndent) && indent.Length > parentIndent.Length && IsBlank(indent))
				{
					mIndentUnit.Set(indent.Substring(parentIndent.Length));
					mMultiLine = true;
				}
			}
			if (mColonText.IsEmpty && mStyles[id].mNameEnd >= 0)
			{
				StringView colon = .(mSource + mStyles[id].mNameEnd, mStyles[id].mValueStart - mStyles[id].mNameEnd);
				if (IsBlank(colon.Substring(0, colon.IndexOf(':'))) && IsBlank(colon.Substring(colon.IndexOf(':') + 1)))
					mColonText.Set(colon);
			}
			if (!mIndentUnit.IsEmpty && !mColonText.IsEmpty)
				break;
		}
		// A root container with a line break inside (even `{\n}`) is a document written on several lines
		ref JsonNodeStyle root = ref mStyles[mRoot];
		if (!mMultiLine && mNodes[mRoot].IsContainer)
			mMultiLine = HasLineBreak(.(mSource + root.mValueStart, root.mValueEnd - root.mValueStart));
		if (mIndentUnit.IsEmpty)
			mIndentUnit.Set("  ");
		if (mColonText.IsEmpty)
			mColonText.Set(mMultiLine ? ": " : ":");
		mNewLine.Set("\n");
		for (int i < mSourceLength)
		{
			if (mSource[i] == '\r')
			{
				mNewLine.Set(i + 1 < mSourceLength && mSource[i + 1] == '\n' ? "\r\n" : "\r");
				break;
			}
			if (mSource[i] == '\n')
				break;
		}
	}

	static bool IsBlank(StringView text)
	{
		for (let c in text)
		{
			if (c != ' ' && c != '\t')
				return false;
		}
		return true;
	}

	/// A captured node's leading trivia.
	StringView LeadingOf(uint32 id)
	{
		ref JsonNodeStyle style = ref mStyles[id];
		return .(mSource + style.mLeadStart, style.mTokenStart - style.mLeadStart);
	}

	[Inline]
	bool IsCaptured(uint32 id)
	{
		return id < (uint32)mStyles.Count && mStyles[id].mFlags.HasFlag(.Captured);
	}

	/// The indentation of the line node `id` starts on: up to the nearest captured node whose leading
	/// trivia has a line break (the blanks after it; a captured node on the same line as the separator
	/// before it is on its container's line), plus a unit for each node added in code on the way. The
	/// root's line has none.
	void IndentOf(uint32 id, String output)
	{
		int levels = 0;
		uint32 at = id;
		while (at != 0 && mNodes[at].mParent != 0)
		{
			if (IsCaptured(at))
			{
				let leading = LeadingOf(at);
				int newline = Math.Max(leading.LastIndexOf('\n'), leading.LastIndexOf('\r'));
				if (newline >= 0)
				{
					int blank = newline + 1;
					while (blank < leading.Length && (leading[blank] == ' ' || leading[blank] == '\t'))
						blank++;
					output.Append(leading.Substring(newline + 1, blank - newline - 1));
					break;
				}
			}
			else
				levels++;
			at = mNodes[at].mParent;
		}
		for (int i < levels)
			output.Append(mIndentUnit);
	}

	// Change marks

	/// Marks `flags` on `id` and SubtreeDirty up its ancestors, so they are written piece by piece
	/// (PreserveStyle documents only).
	internal void Mark(uint32 id, JsonStyleFlags flags)
	{
		if (!mPreserve)
			return;
		StyleOf(id).mFlags |= flags;
		uint32 parent = mNodes[id].mParent;
		while (parent != 0)
		{
			ref JsonNodeStyle style = ref StyleOf(parent);
			if (style.mFlags.HasFlag(.SubtreeDirty))
				break;
			style.mFlags |= .SubtreeDirty;
			parent = mNodes[parent].mParent;
		}
	}

	internal void MarkValueChanged(uint32 id) => Mark(id, .ValueDirty | .SubtreeDirty);
	/// (The value keeps its text: only the name is regenerated.)
	internal void MarkNameChanged(uint32 id) => Mark(id, .NameDirty);
	internal void MarkChildrenChanged(uint32 id) => Mark(id, .ChildrenDirty | .SubtreeDirty);

	/// A node added in code (or a new root): nothing of it is in the source.
	internal void MarkNew(uint32 id)
	{
		if (!mPreserve)
			return;
		ref JsonNodeStyle style = ref StyleOf(id);
		style = default;
		style.mNameEnd = -1;
		style.mCommaPos = -1;
		Mark(id, .SubtreeDirty);
	}

	// The preserving writer

	/// The PreserveStyle document as it was read, with what changed regenerated: unchanged values are
	/// their source text; a changed one keeps its surroundings (comments, blank lines, the comma after
	/// it); a new one takes the layout of its siblings. Commas follow the members that remain (a removed
	/// last member takes the comma before it along; a trailing comma stays with the last member). The
	/// walk is iterative.
	Result<void, JsonWriteError> WritePreserving(String output)
	{
		if (mRoot == 0)
			return .Err(JsonWriteError(.InvalidStructure, "The document is empty"));
		let writer = scope JsonWriter(output);
		// Before the root: its leading trivia (or, for a root added in code, the old one's)
		ref JsonNodeStyle rootStyle = ref StyleOf(mRoot);
		if (rootStyle.mFlags.HasFlag(.Captured))
			output.Append(mSource, rootStyle.mTokenStart);
		else
			output.Append(mSource, mDocLeadEnd);
		// Containers being written piece by piece
		let open = scope List<uint32>();
		uint32 id = mRoot;
		while (true)
		{
			// The node's value (its leading and name were written by its parent's loop)
			ref JsonNodeStyle style = ref StyleOf(id);
			ref JsonNodeRecord node = ref mNodes[id];
			bool captured = style.mFlags.HasFlag(.Captured);
			bool descend = false;
			if (captured && !style.mFlags.HasFlag(.SubtreeDirty))
				output.Append(mSource + style.mValueStart, style.mValueEnd - style.mValueStart);
			else if (node.IsContainer)
			{
				output.Append(node.mKind == .Object ? '{' : '[');
				open.Add(id);
				descend = true;
			}
			else
				WriteScalarText(writer, output, id);
			// The next piece: the first child, or what follows this value in its container
			uint32 next = descend ? FirstLive(id) : 0;
			if (descend && next != 0)
			{
				WriteBefore(output, next);
				id = next;
				continue;
			}
			// Closing what ended
			uint32 done = id;
			while (true)
			{
				if (descend && open.Back == done)
				{
					WriteClose(output, done);
					open.PopBack();
					descend = false;
				}
				if (done == mRoot)
				{
					// After the root: the source's tail
					if (writer.HasError)
						return writer.Finish();
					output.Append(mSource + mDocTrailStart, mSourceLength - mDocTrailStart);
					return .Ok;
				}
				uint32 sibling = mNodes[done].mNext;
				WriteAfter(output, done, sibling != 0);
				if (sibling != 0)
				{
					WriteBefore(output, sibling);
					id = sibling;
					break;
				}
				done = mNodes[done].mParent;
				descend = true;
			}
		}
	}

	[Inline]
	uint32 FirstLive(uint32 id)
	{
		return mNodes[id].mFirstChild;
	}

	/// A child's leading trivia and, in an object, its name and colon.
	void WriteBefore(String output, uint32 id)
	{
		ref JsonNodeStyle style = ref StyleOf(id);
		uint32 parent = mNodes[id].mParent;
		bool captured = style.mFlags.HasFlag(.Captured);
		if (captured)
		{
			StringView leading = .(mSource + style.mLeadStart, style.mTokenStart - style.mLeadStart);
			// First now but not before, on the line of the separator it followed: the first child's layout
			if (mNodes[id].mPrev == 0 && IsCaptured(parent) && style.mLeadStart != StyleOf(parent).mValueStart + 1 && !HasLineBreak(leading))
				FirstLayout(output, parent);
			else
				output.Append(leading);
		}
		else
			NewLeading(output, id);
		if (mNodes[parent].mKind != .Object)
			return;
		if (captured && !style.mFlags.HasFlag(.NameDirty))
		{
			output.Append(mSource + style.mTokenStart, style.mValueStart - style.mTokenStart);
			return;
		}
		output.Append('"');
		JsonWriter.AppendEscaped(output, NameOf(id), .());
		output.Append('"');
		if (captured && style.mNameEnd >= 0)
			output.Append(mSource + style.mNameEnd, style.mValueStart - style.mNameEnd);
		else
			output.Append(mColonText);
	}

	/// What follows a child: its trailing trivia, and its comma when another child follows or it is
	/// still the last one it was (a trailing comma); without a comma, the rest of its comma's line stays.
	void WriteAfter(String output, uint32 id, bool hasNext)
	{
		ref JsonNodeStyle style = ref StyleOf(id);
		ref JsonNodeStyle parent = ref StyleOf(mNodes[id].mParent);
		// The last child of a container written with a trailing comma keeps one
		bool trailingComma = !hasNext && parent.mFlags.HasFlag(.TrailingComma) && !parent.mFlags.HasFlag(.ValueDirty);
		bool captured = style.mFlags.HasFlag(.Captured);
		if (!captured)
		{
			if (hasNext || trailingComma)
				output.Append(',');
			return;
		}
		if (style.mCommaPos < 0)
		{
			// The last child it was: a comma now goes before the comments on its line
			if (hasNext || trailingComma)
				output.Append(',');
			output.Append(mSource + style.mValueEnd, style.mAfterEnd - style.mValueEnd);
			return;
		}
		output.Append(mSource + style.mValueEnd, style.mCommaPos - style.mValueEnd);
		if (hasNext || trailingComma)
			output.Append(mSource + style.mCommaPos, style.mAfterEnd - style.mCommaPos);
		else
			output.Append(mSource + style.mCommaPos + 1, style.mAfterEnd - style.mCommaPos - 1);
	}

	/// A container's end, written piece by piece: the trivia before its bracket, and the bracket.
	void WriteClose(String output, uint32 id)
	{
		ref JsonNodeStyle style = ref StyleOf(id);
		ref JsonNodeRecord node = ref mNodes[id];
		bool captured = style.mFlags.HasFlag(.Captured) && !style.mFlags.HasFlag(.ValueDirty);
		bool hadChildren = captured && style.mInnerStart > style.mValueStart + 1;
		StringView inner = captured ? StringView(mSource + style.mInnerStart, style.mCloseStart - style.mInnerStart) : default;
		// An empty container written on several lines (`[\n]`) keeps its lines around new children
		if (captured && (hadChildren || node.mFirstChild == 0 || HasLineBreak(inner)))
			output.Append(inner);
		else if (node.mFirstChild != 0 && mMultiLine)
		{
			output.Append(mNewLine);
			IndentOf(id, output);
		}
		output.Append(node.mKind == .Object ? '}' : ']');
	}

	/// The leading trivia of a value added in code: a captured sibling's line break and indentation (or
	/// its blanks, in a container on one line), else a line break and the container's indentation plus a
	/// unit (in a document written on several lines), else nothing.
	static bool HasLineBreak(StringView text)
	{
		return text.Contains('\n') || text.Contains('\r');
	}

	/// The layout of a container's first child in the source (a line break and indentation, or the
	/// blanks after the bracket), without its comments.
	void FirstLayout(String output, uint32 container)
	{
		ref JsonNodeStyle style = ref StyleOf(container);
		if (style.mFirstToken < 0)
			return;
		StringView leading = .(mSource + style.mValueStart + 1, style.mFirstToken - style.mValueStart - 1);
		AppendLayout(output, leading);
	}

	/// The layout part of leading trivia: from its last line break (a CRLF whole) through the indentation
	/// after it, or the whole text when it is blank and on one line, else nothing.
	static void AppendLayout(String output, StringView leading)
	{
		int newline = Math.Max(leading.LastIndexOf('\n'), leading.LastIndexOf('\r'));
		if (newline >= 0)
		{
			int from = newline > 0 && leading[newline] == '\n' && leading[newline - 1] == '\r' ? newline - 1 : newline;
			int end = newline + 1;
			while (end < leading.Length && (leading[end] == ' ' || leading[end] == '\t'))
				end++;
			output.Append(leading.Substring(from, end - from));
		}
		else if (IsBlank(leading))
			output.Append(leading);
	}

	void NewLeading(String output, uint32 id)
	{
		uint32 parent = mNodes[id].mParent;
		uint32 first = mNodes[parent].mFirstChild;
		int32 openEnd = IsCaptured(parent) ? StyleOf(parent).mValueStart + 1 : -1;
		bool capturedSibling = false;
		StringView between = default;
		bool hasBetween = false;
		for (uint32 sibling = first; sibling != 0; sibling = mNodes[sibling].mNext)
		{
			if (sibling == id || !IsCaptured(sibling))
				continue;
			capturedSibling = true;
			let leading = LeadingOf(sibling);
			if (HasLineBreak(leading))
			{
				AppendLayout(output, leading);
				return;
			}
			// On one line: the spacing after a comma, from a sibling that followed one in the source
			if (mStyles[sibling].mLeadStart != openEnd && !hasBetween && IsBlank(leading))
			{
				between = leading;
				hasBetween = true;
			}
		}
		if (capturedSibling)
		{
			if (id == first)
				FirstLayout(output, parent);
			else
				output.Append(hasBetween ? between : mMultiLine ? " " : "");
			return;
		}
		// No sibling to follow: on lines of their own in a document written on several lines, or in an
		// empty container that is (`[\n]`)
		bool multiLine = mMultiLine;
		if (!multiLine && IsCaptured(parent))
		{
			ref JsonNodeStyle container = ref StyleOf(parent);
			multiLine = container.mInnerStart == container.mValueStart + 1 &&
				HasLineBreak(.(mSource + container.mInnerStart, container.mCloseStart - container.mInnerStart));
		}
		if (multiLine)
		{
			output.Append(mNewLine);
			IndentOf(id, output);
		}
	}

	/// A scalar's text, written fresh.
	void WriteScalarText(JsonWriter writer, String output, uint32 id)
	{
		ref JsonNodeRecord node = ref mNodes[id];
		switch (node.mKind)
		{
		case .Null: output.Append("null");
		case .True: output.Append("true");
		case .False: output.Append("false");
		case .String:
			output.Append('"');
			if (!JsonWriter.AppendEscaped(output, ValueTextOf(id), .()))
				writer.Fail(.InvalidUtf8, "A string is not well-formed UTF-8");
			output.Append('"');
		case .Number:
			AppendNumber(output, id, .Plain);
		default:
		}
	}
}
