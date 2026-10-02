using System;
using System.Collections;
using System.Reflection;

namespace JsonBeef;

/// @brief The compile-time half of [JsonObject]: writes the Beef source of a type's JsonRead (straight
/// from the reader's tokens, no document in between) and JsonWrite (to a JsonWriter, and into a JsonNode
/// in place) and hands it to the compiler. Nothing here runs in the finished program; the emitted code
/// calls JsonBind for the per-value work. (XmlBeef's and KdlBeef's generators, with JSON's shapes.)
///
/// Emitted names are fully qualified (the user's file needs no `using JsonBeef`), fields are reached
/// through `this.` and locals start with `_`, so neither clashes with the type's own members. Members
/// are matched by trying the next declared one first, then a switch on the name's length, always by
/// comparing the bytes (no hash-only matching). Enums are generated switches over their case names.
///
/// The planning (value specs, member names, checks) is in JsonSerializerPlan.bf; this file is the entry
/// point and the emission of code from the plans.
public static class JsonSerializerCodeGen
{
	/// A component of the path generated code prepends to an error leaving a nested value: a member name
	/// (a literal or a String expression) or an array index (an int expression).
	class PathPart
	{
		public bool mIsIndex;
		public String mExpr = new .() ~ delete _;

		public this(bool isIndex, StringView expr)
		{
			mIsIndex = isIndex;
			mExpr.Set(expr);
		}
	}

	/// Code being written, with a counter for unique local names.
	class Emitter
	{
		public String mCode = new .() ~ delete _;
		public int mNext;
		public String mOwner = new .() ~ delete _;
		public String mField = new .() ~ delete _;
		public List<PathPart> mPath = new .() ~ DeleteContainerAndItems!(_);
		/// The naming of the field being emitted (enum case names follow it).
		public JsonNaming mNaming;

		public this()
		{
		}

		/// A fresh local name: `_<prefix><n>`.
		public String Local(StringView prefix, String name)
		{
			name.AppendF("_{}{}", prefix, mNext++);
			return name;
		}

		/// `error` (an expression of type JsonParseError) with the current path prepended to its own.
		public void Wrap(StringView error, String result)
		{
			let expr = scope String(error);
			for (int i = mPath.Count - 1; i >= 0; i--)
			{
				let part = mPath[i];
				let wrapped = scope String();
				wrapped.AppendF("JsonBeef.JsonBind.{}({}, {})", part.mIsIndex ? "AtIndex" : "AtMember", expr, part.mExpr);
				expr.Set(wrapped);
			}
			result.Append(expr);
		}

		/// `return .Err(<wrapped error>);`
		public void Return(StringView indent, StringView error)
		{
			mCode.AppendF("{}return .Err(", indent);
			Wrap(error, mCode);
			mCode.Append(");\n");
		}

		/// `return .Err(<wrapped JsonBind.Error(_rd)>);`
		public void ReturnBind(StringView indent)
		{
			Return(indent, "JsonBeef.JsonBind.Error(_rd)");
		}
	}

	/// @brief Emit IJsonSerializable into `type`: the methods' signatures now, their bodies when they
	/// are compiled (Body), when every type is complete, so that a type can hold itself
	/// (`List<Node> children`) without a cycle in the type's initialization.
	/// @param type A class or struct carrying [JsonObject].
	/// @param attribute Its [JsonObject].
	[Comptime]
	public static void Emit(Type type, JsonObjectAttribute attribute)
	{
		let ownerName = type.GetFullName(.. scope .());
		bool baseIsObject = !type.IsValueType && type.BaseType != null && type.BaseType != typeof(Object) && type.BaseType.HasCustomAttribute<JsonObjectAttribute>();
		StringView modifier = type.IsValueType ? "" : baseIsObject ? "override " : "virtual ";
		StringView mutable = type.IsValueType ? " mut" : "";
		let typeExpr = scope $"typeof({ownerName})";

		if (!baseIsObject)
			Compiler.EmitAddInterface(type, typeof(IJsonSerializable));
		let code = scope String();
		code.AppendF("public {}Result<void, JsonBeef.JsonParseError> JsonRead(JsonBeef.JsonReader _rd, System.ITypedAllocator _alloc = null){}\n{{\n\tSystem.Compiler.Mixin(JsonBeef.JsonSerializerCodeGen.Body({}, 0));\n}}\n", modifier, mutable, typeExpr);
		code.AppendF("public {}void JsonWrite(JsonBeef.JsonWriter _w)\n{{\n\tSystem.Compiler.Mixin(JsonBeef.JsonSerializerCodeGen.Body({}, 1));\n}}\n", modifier, typeExpr);
		code.AppendF("public {}Result<void, JsonBeef.JsonWriteError> JsonWrite(JsonBeef.JsonNode _node)\n{{\n\tSystem.Compiler.Mixin(JsonBeef.JsonSerializerCodeGen.Body({}, 2));\n}}\n", modifier, typeExpr);
		if (attribute.ShowGenerated)
		{
			bool hides = false;
			if (baseIsObject && type.BaseType.GetCustomAttribute<JsonObjectAttribute>() case .Ok(let baseObject))
				hides = baseObject.ShowGenerated;
			code.AppendF("public {}static StringView JsonGeneratedSource\n{{\n\tget\n\t{{\n\t\tSystem.Compiler.Mixin(JsonBeef.JsonSerializerCodeGen.SourceReturn({}));\n\t}}\n}}\n", hides ? "new " : "", typeExpr);
		}
		Compiler.EmitTypeBody(type, code);
	}

	/// @brief The body of one generated method of `type`, mixed in when the method is compiled.
	/// @param type The [JsonObject] type.
	/// @param part 0: JsonRead(JsonReader), 1: JsonWrite(JsonWriter), 2: JsonWrite(JsonNode).
	/// @return The code.
	[Comptime]
	public static String Body(Type type, int part)
	{
		JsonObjectAttribute attribute = default;
		if (type.GetCustomAttribute<JsonObjectAttribute>() case .Ok(let found))
			attribute = found;
		let ownerName = type.GetFullName(.. scope .());
		let plan = PlanType(type, attribute, ownerName);
		defer delete plan;
		let e = scope Emitter();
		e.mOwner.Set(ownerName);
		switch (part)
		{
		case 0: EmitRead(e, type, plan, attribute);
		case 1: EmitWrite(e, plan, attribute);
		default: EmitWriteNode(e, plan, attribute);
		}
		return new String(e.mCode);
	}

	/// @brief `return "<the generated code of type>";` (for [JsonObject(ShowGenerated = true)]).
	/// @param type The [JsonObject] type.
	/// @return The statement.
	[Comptime]
	public static String SourceReturn(Type type)
	{
		let all = scope String();
		for (int part < 3)
		{
			let body = Body(type, part);
			all.Append(body);
			delete body;
		}
		let code = new String("return ");
		AppendLiteral(code, all, true);
		code.Append(';');
		return code;
	}

	// Reading

	[Comptime]
	static void EmitRead(Emitter e, Type type, TypePlan plan, JsonObjectAttribute attribute)
	{
		let code = e.mCode;
		code.Append("\tif (!JsonBeef.JsonBind.BeginObject(_rd))\n\t\treturn .Err(JsonBeef.JsonBind.Error(_rd));\n");
		bool anyRequired = false;
		for (let field in plan.mFields)
			anyRequired |= field.mRequired;
		if (anyRequired)
			code.Append("\tint _start = _rd.Offset;\n");
		int words = (plan.mSlots + 63) / 64;
		if (words > 0)
			code.AppendF("\tuint64[{}] _seen = default;\n\tint _next = 0;\n", words);
		code.Append("\twhile (true)\n\t{\n");
		code.Append("\t\tlet _step = JsonBeef.JsonBind.NextMember(_rd);\n\t\tif (_step != .Item)\n\t\t{\n\t\t\tif (_step == .Error)\n\t\t\t\treturn .Err(JsonBeef.JsonBind.Error(_rd));\n\t\t\tbreak;\n\t\t}\n");
		code.Append("\t\tint _f = -1;\n");
		if (plan.mSlots > 0)
			code.Append("\t\tStringView _name = _rd.StringValue;\n");

		// The slots in order (the discriminator first), each with its names
		let slotNames = scope List<List<StringView>>();
		defer { ClearAndDeleteItems!(slotNames); }
		for (int s < plan.mSlots)
			slotNames.Add(new .());
		if (plan.mDiscriminatorSlot >= 0)
			slotNames[plan.mDiscriminatorSlot].Add(plan.mDiscriminator);
		for (let field in plan.mFields)
		{
			slotNames[field.mSlot].Add(field.mName);
			for (let alias in field.mAliases)
				slotNames[field.mSlot].Add(alias);
		}

		if (plan.mSlots > 0)
		{
			// The next slot's name first (members usually come in the declared order)
			code.Append("\t\tswitch (_next)\n\t\t{\n");
			for (int s < plan.mSlots)
				code.AppendF("\t\tcase {}: if (_name == {}) _f = {};\n", s, AppendLiteral(.. scope .(), slotNames[s][0]), s);
			code.Append("\t\tdefault:\n\t\t}\n");
			// Else by length, then the bytes
			let byLength = scope Dictionary<int, String>();
			defer { for (let entry in byLength) delete entry.value; }
			for (int s < plan.mSlots)
			{
				for (let name in slotNames[s])
				{
					if (!byLength.TryGetValue(name.Length, var tests))
					{
						tests = new String();
						byLength[name.Length] = tests;
					}
					else
						tests.Append(" else ");
					tests.AppendF("if (_name == {}) _f = {};", AppendLiteral(.. scope .(), name), s);
				}
			}
			let lengths = scope List<int>();
			for (let length in byLength.Keys)
				lengths.Add(length);
			lengths.Sort();
			code.Append("\t\tif (_f < 0)\n\t\t{\n\t\t\tswitch (_name.Length)\n\t\t\t{\n");
			for (let length in lengths)
				code.AppendF("\t\t\tcase {}: {}\n", length, byLength[length]);
			code.Append("\t\t\tdefault:\n\t\t\t}\n\t\t}\n");
			// A second member for a slot
			code.Append("\t\tif (_f >= 0)\n\t\t{\n\t\t\tuint64 _bit = 1UL << (_f & 63);\n\t\t\tif ((_seen[_f >> 6] & _bit) != 0)\n\t\t\t{\n");
			code.Append("\t\t\t\tswitch (JsonBeef.JsonBind.OnDuplicate(_rd))\n\t\t\t\t{\n\t\t\t\tcase .Error: return .Err(JsonBeef.JsonBind.Error(_rd));\n\t\t\t\tcase .Skip: _f = -2;\n\t\t\t\tcase .Read:\n\t\t\t\t}\n\t\t\t}\n");
			code.Append("\t\t\tif (_f >= 0)\n\t\t\t{\n\t\t\t\t_seen[_f >> 6] |= _bit;\n\t\t\t\t_next = _f + 1;\n\t\t\t}\n\t\t}\n");
		}
		if (attribute.Strict)
			code.Append("\t\tif (_f == -1)\n\t\t\treturn .Err(JsonBeef.JsonBind.Unknown(_rd));\n");
		code.Append("\t\tif (!JsonBeef.JsonBind.Value(_rd))\n\t\t\treturn .Err(JsonBeef.JsonBind.Error(_rd));\n");
		code.Append("\t\tswitch (_f)\n\t\t{\n");
		if (plan.mDiscriminatorSlot >= 0)
		{
			code.AppendF("\t\tcase {}:\n\t\t\tif (!JsonBeef.JsonBind.CheckTypeName(_rd, {}, {}))\n\t\t\t\treturn .Err(JsonBeef.JsonBind.AtMember(JsonBeef.JsonBind.Error(_rd), {}));\n",
				plan.mDiscriminatorSlot, AppendLiteral(.. scope .(), plan.mDiscriminator), AppendLiteral(.. scope .(), plan.mTypeName), AppendLiteral(.. scope .(), plan.mDiscriminator));
		}
		for (let field in plan.mFields)
		{
			code.AppendF("\t\tcase {}:\n", field.mSlot);
			e.mField.Set(field.mField.Name);
			e.mNaming = field.mNaming;
			e.mPath.Add(new .(false, AppendLiteral(.. scope .(), field.mName)));
			let target = scope $"this.{field.mField.Name}";
			EmitReadValue(e, "\t\t\t", field.mSpec, target, scope $"{target} = {{0}};");
			delete e.mPath.PopBack();
		}
		code.Append("\t\tdefault:\n\t\t\tif (!JsonBeef.JsonBind.Skip(_rd))\n\t\t\t\treturn .Err(JsonBeef.JsonBind.Error(_rd));\n\t\t}\n\t}\n");

		// Required members
		for (let field in plan.mFields)
		{
			if (!field.mRequired)
				continue;
			code.AppendF("\tif ((_seen[{}] & {}UL) == 0)\n\t\treturn .Err(JsonBeef.JsonBind.Missing(_rd, _start, {}));\n", field.mSlot >> 6, 1UL << (field.mSlot & 63), AppendLiteral(.. scope .(), field.mName));
		}
		code.Append("\treturn .Ok;\n");
	}

	/// Reads the value the current token starts into `existing` (a field, kept and filled where it can
	/// be: a String set, an object read into, a List or Dictionary emptied and refilled), or when
	/// `existing` is empty into a new value handed to `assign` (a statement with `{0}` for the value).
	[Comptime]
	static void EmitReadValue(Emitter e, StringView indent, ValueSpec spec, StringView existing, StringView assign)
	{
		let code = e.mCode;
		let typeName = spec.mType.GetFullName(.. scope .());
		let inner = scope $"{indent}\t";
		switch (spec.mKind)
		{
		case .Bool:
			let local = e.Local("b", .. scope .());
			code.AppendF("{}{{\n{}bool {};\n{}if (!JsonBeef.JsonBind.ReadBool(_rd, out {}))\n", indent, inner, local, inner, local);
			e.ReturnBind(scope $"{inner}\t");
			Assign(code, inner, assign, local);
			code.AppendF("{}}}\n", indent);
		case .Integer:
			let local = e.Local("i", .. scope .());
			if (IsUInt64(spec.mType))
				code.AppendF("{}{{\n{}uint64 {};\n{}if (!JsonBeef.JsonBind.ReadUInt64(_rd, out {}))\n", indent, inner, local, inner, local);
			else
			{
				let min = scope String();
				let max = scope String();
				IntegerRange(spec.mType, min, max);
				code.AppendF("{}{{\n{}int64 {};\n{}if (!JsonBeef.JsonBind.ReadInteger(_rd, {}, {}, out {}))\n", indent, inner, local, inner, min, max, local);
			}
			e.ReturnBind(scope $"{inner}\t");
			Assign(code, inner, assign, scope $"({typeName}){local}");
			code.AppendF("{}}}\n", indent);
		case .Float:
			let local = e.Local("d", .. scope .());
			bool isFloat = spec.mType == typeof(float);
			code.AppendF("{}{{\n{}{} {};\n{}if (!JsonBeef.JsonBind.{}(_rd, out {}))\n", indent, inner, isFloat ? "float" : "double", local, inner, isFloat ? "ReadFloat" : "ReadDouble", local);
			e.ReturnBind(scope $"{inner}\t");
			Assign(code, inner, assign, local);
			code.AppendF("{}}}\n", indent);
		case .String:
			if (!existing.IsEmpty)
			{
				code.AppendF("{}if (!JsonBeef.JsonBind.ReadString(_rd, ref {}, _alloc))\n", indent, existing);
				e.ReturnBind(inner);
			}
			else
			{
				let local = e.Local("s", .. scope .());
				code.AppendF("{}{{\n{}String {} = null;\n{}if (!JsonBeef.JsonBind.ReadString(_rd, ref {}, _alloc))\n", indent, inner, local, inner, local);
				e.ReturnBind(scope $"{inner}\t");
				Assign(code, inner, assign, local);
				code.AppendF("{}}}\n", indent);
			}
		case .Enum:
			EmitReadEnum(e, indent, spec, assign);
		case .Converter:
			let converterName = spec.mConverter.GetFullName(.. scope .());
			if (!existing.IsEmpty)
			{
				code.AppendF("{}if ({}.Read(_rd, ref {}) case .Err(let _ce))\n", indent, converterName, existing);
				e.Return(inner, "_ce");
			}
			else
			{
				let local = e.Local("c", .. scope .());
				code.AppendF("{}{{\n{}{} {} = default;\n{}if ({}.Read(_rd, ref {}) case .Err(let _ce))\n", indent, inner, typeName, local, inner, converterName, local);
				e.Return(scope $"{inner}\t", "_ce");
				Assign(code, inner, assign, local);
				code.AppendF("{}}}\n", indent);
			}
		case .Nullable:
			code.AppendF("{}if (_rd.TokenType == .Null)\n", indent);
			Assign(code, inner, assign, "null");
			code.AppendF("{}else\n{}{{\n", indent, indent);
			EmitReadValue(e, inner, spec.mItem, "", assign);
			code.AppendF("{}}}\n", indent);
		case .Object:
			EmitReadObject(e, indent, spec, existing, assign);
		case .List:
			EmitReadList(e, indent, spec, existing, assign);
		case .Dictionary:
			EmitReadDictionary(e, indent, spec, existing, assign);
		default:
		}
	}

	/// `assign` with `value` for `{0}`.
	[Comptime]
	static void Assign(String code, StringView indent, StringView assign, StringView value)
	{
		code.Append(indent);
		code.Append(scope String(assign)..Replace("{0}", value));
		code.Append('\n');
	}

	[Comptime]
	static void EmitReadEnum(Emitter e, StringView indent, ValueSpec spec, StringView assign)
	{
		let code = e.mCode;
		let inner = scope $"{indent}\t";
		let typeName = spec.mType.GetFullName(.. scope .());
		let local = e.Local("e", .. scope .());
		let naming = CaseNaming(e);
		if (spec.mEnumNumbers)
		{
			let number = e.Local("i", .. scope .());
			code.AppendF("{}{{\n{}int64 {};\n{}if (!JsonBeef.JsonBind.ReadInteger(_rd, int64.MinValue, int64.MaxValue, out {}))\n", indent, inner, number, inner, number);
			e.ReturnBind(scope $"{inner}\t");
			code.AppendF("{}{} {} = ({}){};\n{}if (!(", inner, typeName, local, typeName, number, inner);
			EmitIsCase(code, spec.mType, local);
			code.Append("))\n");
			e.Return(scope $"{inner}\t", scope $"JsonBeef.JsonBind.UnknownNumber(_rd, {AppendLiteral(.. scope .(), typeName)})");
		}
		else
		{
			let text = e.Local("t", .. scope .());
			code.AppendF("{}{{\n{}StringView {};\n{}if (!JsonBeef.JsonBind.ReadText(_rd, out {}))\n", indent, inner, text, inner, text);
			e.ReturnBind(scope $"{inner}\t");
			code.AppendF("{}{} {};\n{}switch ({})\n{}{{\n", inner, typeName, local, inner, text, inner);
			let cases = scope String();
			for (let field in spec.mType.GetFields())
			{
				if (!field.IsEnumCase)
					continue;
				let name = ApplyNaming(field.Name, naming, .. scope .());
				if (!cases.IsEmpty)
					cases.Append(", ");
				cases.Append(name);
				code.AppendF("{}case {}: {} = .{};\n", inner, AppendLiteral(.. scope .(), name), local, field.Name);
			}
			code.AppendF("{}default:\n", inner);
			e.Return(scope $"{inner}\t", scope $"JsonBeef.JsonBind.UnknownCase(_rd, {AppendLiteral(.. scope .(), cases)})");
			code.AppendF("{}}}\n", inner);
		}
		Assign(code, inner, assign, local);
		code.AppendF("{}}}\n", indent);
	}

	/// The naming enum cases are written in: that of the [JsonObject] level declaring the field.
	[Comptime]
	static JsonNaming CaseNaming(Emitter e)
	{
		return e.mNaming;
	}

	[Comptime]
	static void EmitReadObject(Emitter e, StringView indent, ValueSpec spec, StringView existing, StringView assign)
	{
		let code = e.mCode;
		let inner = scope $"{indent}\t";
		let typeName = spec.mType.GetFullName(.. scope .());
		if (spec.mType.IsValueType)
		{
			code.AppendF("{}if (!JsonBeef.JsonBind.NotNull(_rd, \"an object\"))\n", indent);
			e.ReturnBind(inner);
			if (!existing.IsEmpty)
			{
				code.AppendF("{}if ({}.JsonRead(_rd, _alloc) case .Err(let _oe))\n", indent, existing);
				e.Return(inner, "_oe");
			}
			else
			{
				let local = e.Local("o", .. scope .());
				code.AppendF("{}{{\n{}{} {} = .();\n{}if ({}.JsonRead(_rd, _alloc) case .Err(let _oe))\n", indent, inner, typeName, local, inner, local);
				e.Return(scope $"{inner}\t", "_oe");
				Assign(code, inner, assign, local);
				code.AppendF("{}}}\n", indent);
			}
			return;
		}
		// A class: null, or the object (an existing one read into, unless the type is polymorphic)
		code.AppendF("{}if (_rd.TokenType == .Null)\n{}{{\n", indent, indent);
		if (!existing.IsEmpty)
			code.AppendF("{}if (_alloc == null)\n{}\tdelete {};\n", inner, inner, existing);
		Assign(code, inner, assign, "null");
		code.AppendF("{}}}\n{}else\n{}{{\n", indent, indent, indent);
		if (spec.mPolymorphic)
		{
			let name = e.Local("tn", .. scope .());
			let found = e.Local("fd", .. scope .());
			let discriminator = DiscriminatorOf(spec.mType, .. scope .());
			code.AppendF("{}if (!JsonBeef.JsonBind.BeginObject(_rd))\n", inner);
			e.ReturnBind(scope $"{inner}\t");
			code.AppendF("{}let {} = scope String();\n{}bool {};\n{}if (!JsonBeef.JsonBind.ReadDiscriminator(_rd, {}, {}, out {}))\n", inner, name, inner, found, inner, AppendLiteral(.. scope .(), discriminator), name, found);
			e.ReturnBind(scope $"{inner}\t");
			if (!existing.IsEmpty)
				code.AppendF("{0}if (_alloc == null)\n{0}\tdelete {1};\n{0}{1} = null;\n", inner, existing);
			// The subtypes are found when this method is compiled, not now: they derive from the type,
			// which may be the one being generated and not complete yet
			let wrapped = e.Wrap("{1}", .. scope .());
			code.AppendF("{}System.Compiler.Mixin(JsonBeef.JsonSerializerCodeGen.TypeDispatch(typeof({}), {}, {}, {}, {}, {}, {}));\n", inner, typeName,
				AppendLiteral(.. scope .(), e.mOwner), AppendLiteral(.. scope .(), e.mField), AppendLiteral(.. scope .(), name), AppendLiteral(.. scope .(), found),
				AppendLiteral(.. scope .(), assign), AppendLiteral(.. scope .(), wrapped));
		}
		else if (!existing.IsEmpty)
		{
			code.AppendF("{0}if ({1} == null)\n{0}\t{1} = {2};\n{0}if ({1}.JsonRead(_rd, _alloc) case .Err(let _oe))\n", inner, existing, NewExpr(typeName, .. scope .()));
			e.Return(scope $"{inner}\t", "_oe");
		}
		else
		{
			// Handed over before it is read, so it is owned even if reading fails
			let local = e.Local("o", .. scope .());
			code.AppendF("{}let {} = {};\n", inner, local, NewExpr(typeName, .. scope .()));
			Assign(code, inner, assign, local);
			code.AppendF("{}if ({}.JsonRead(_rd, _alloc) case .Err(let _oe))\n", inner, local);
			e.Return(scope $"{inner}\t", "_oe");
		}
		code.AppendF("{}}}\n", indent);
	}

	/// @brief The `switch` that creates and reads the object the current StartObject starts as the type
	/// its discriminator names, among `baseType` and its [JsonObject] subclasses. Mixed into the generated
	/// JsonRead when it is compiled.
	/// @param baseType The field's (or item's) class.
	/// @param ownerName The type holding the field, for errors.
	/// @param fieldName The field, for errors.
	/// @param nameLocal The local holding the discriminator's value.
	/// @param foundLocal The local saying whether the object has one.
	/// @param assign The statement that hands the new object over (`{0}` for it).
	/// @param wrap The expression that adds the path to an error (`{1}` for the error).
	/// @return The code.
	[Comptime]
	public static String TypeDispatch(Type baseType, String ownerName, String fieldName, String nameLocal, String foundLocal, String assign, String wrap)
	{
		let types = scope List<Type>();
		SubTypes(baseType, types);
		if (types.IsEmpty)
			Fail(ownerName, fieldName, scope $"found no concrete [JsonObject] class for {baseType.GetFullName(.. scope .())}: mark its subclasses [JsonObject]");
		let discriminator = DiscriminatorOf(baseType, .. scope .());
		let seen = scope List<String>();
		defer { ClearAndDeleteItems!(seen); }
		for (let type in types)
		{
			let name = TypeNameOf(type, .. new .());
			for (let other in seen)
			{
				if (other == name)
					Fail(ownerName, fieldName, scope $"two classes {baseType.GetFullName(.. scope .())} can hold have the type name \"{name}\"; give one another TypeName");
			}
			seen.Add(name);
		}
		// The names for messages, sorted (the declaration order the types come in can vary)
		let sorted = scope List<StringView>();
		for (let name in seen)
			sorted.Add(name);
		sorted.Sort(scope (a, b) => a.CompareTo(b));
		let expected = scope String();
		for (let name in sorted)
		{
			if (!expected.IsEmpty)
				expected.Append(", ");
			expected.Append(name);
		}
		let code = new String();
		code.AppendF("switch ({})\n{{\n", nameLocal);
		for (int i < types.Count)
		{
			let typeName = types[i].GetFullName(.. scope .());
			code.AppendF("case {}:\n", AppendLiteral(.. scope .(), seen[i]));
			EmitDispatchCase(code, typeName, assign, wrap);
		}
		code.Append("default:\n");
		// No discriminator: the base itself when it can be created
		if (!baseType.IsAbstract)
		{
			code.AppendF("\tif (!{})\n\t{{\n", foundLocal);
			EmitDispatchCase(code, baseType.GetFullName(.. scope .()), assign, wrap, "\t");
			code.Append("\t\tbreak;\n\t}\n");
		}
		code.Append("\treturn .Err(");
		code.Append(scope String(wrap)..Replace("{1}", scope $"JsonBeef.JsonBind.UnknownType(_rd, {AppendLiteral(.. scope .(), discriminator)}, {nameLocal}, {AppendLiteral(.. scope .(), expected)})"));
		code.Append(");\n}\n");
		return code;
	}

	[Comptime]
	static void EmitDispatchCase(String code, StringView typeName, StringView assign, StringView wrap, StringView extra = "")
	{
		code.AppendF("{0}\t{{\n{0}\t\tlet _po = {1};\n{0}\t\t{2}\n{0}\t\tif (_po.JsonRead(_rd, _alloc) case .Err(let _pe))\n{0}\t\t\treturn .Err({3});\n{0}\t}}\n",
			extra, NewExpr(typeName, .. scope .()), scope String(assign)..Replace("{0}", "_po"), scope String(wrap)..Replace("{1}", "_pe"));
	}

	[Comptime]
	static void EmitReadList(Emitter e, StringView indent, ValueSpec spec, StringView existing, StringView assign)
	{
		let code = e.mCode;
		let inner = scope $"{indent}\t";
		let typeName = spec.mType.GetFullName(.. scope .());
		code.AppendF("{}if (_rd.TokenType == .Null)\n{}{{\n", indent, indent);
		if (!existing.IsEmpty)
			EmitDeleteOwned(code, inner, spec, existing);
		Assign(code, inner, assign, "null");
		code.AppendF("{}}}\n{}else\n{}{{\n{}if (!JsonBeef.JsonBind.BeginArray(_rd))\n", indent, indent, indent, inner);
		e.ReturnBind(scope $"{inner}\t");
		let list = e.Local("l", .. scope .());
		if (!existing.IsEmpty)
		{
			code.AppendF("{0}if ({1} == null)\n{0}\t{1} = {2};\n{0}else\n{0}{{\n", inner, existing, NewExpr(typeName, .. scope .()));
			EmitClearItems(code, scope $"{inner}\t", spec, existing);
			code.AppendF("{0}\t{1}.Clear();\n{0}}}\n{0}let {2} = {1};\n", inner, existing, list);
		}
		else
		{
			code.AppendF("{}let {} = {};\n", inner, list, NewExpr(typeName, .. scope .()));
			Assign(code, inner, assign, list);
		}
		let index = e.Local("n", .. scope .());
		let step = e.Local("st", .. scope .());
		let body = scope $"{inner}\t";
		code.AppendF("{0}int {1} = 0;\n{0}while (true)\n{0}{{\n{2}let {3} = JsonBeef.JsonBind.NextElement(_rd);\n{2}if ({3} != .Item)\n{2}{{\n{2}\tif ({3} == .Error)\n", inner, index, body, step);
		e.ReturnBind(scope $"{body}\t\t");
		code.AppendF("{0}\tbreak;\n{0}}}\n", body);
		e.mPath.Add(new .(true, index));
		EmitReadValue(e, body, spec.mItem, "", scope $"{list}.Add({{0}});");
		delete e.mPath.PopBack();
		code.AppendF("{}{}++;\n{}}}\n{}}}\n", body, index, inner, indent);
	}

	[Comptime]
	static void EmitReadDictionary(Emitter e, StringView indent, ValueSpec spec, StringView existing, StringView assign)
	{
		let code = e.mCode;
		let inner = scope $"{indent}\t";
		let typeName = spec.mType.GetFullName(.. scope .());
		let keyName = spec.mKeyType.GetFullName(.. scope .());
		code.AppendF("{}if (_rd.TokenType == .Null)\n{}{{\n", indent, indent);
		if (!existing.IsEmpty)
			EmitDeleteOwned(code, inner, spec, existing);
		Assign(code, inner, assign, "null");
		code.AppendF("{}}}\n{}else\n{}{{\n{}if (!JsonBeef.JsonBind.BeginObject(_rd))\n", indent, indent, indent, inner);
		e.ReturnBind(scope $"{inner}\t");
		let map = e.Local("m", .. scope .());
		if (!existing.IsEmpty)
		{
			code.AppendF("{0}if ({1} == null)\n{0}\t{1} = {2};\n{0}else\n{0}{{\n", inner, existing, NewExpr(typeName, .. scope .()));
			EmitClearItems(code, scope $"{inner}\t", spec, existing);
			code.AppendF("{0}\t{1}.Clear();\n{0}}}\n{0}let {2} = {1};\n", inner, existing, map);
		}
		else
		{
			code.AppendF("{}let {} = {};\n", inner, map, NewExpr(typeName, .. scope .()));
			Assign(code, inner, assign, map);
		}
		let step = e.Local("st", .. scope .());
		let valuePtr = e.Local("vp", .. scope .());
		let keyText = e.Local("kt", .. scope .());
		let body = scope $"{inner}\t";
		code.AppendF("{0}while (true)\n{0}{{\n{1}let {2} = JsonBeef.JsonBind.NextMember(_rd);\n{1}if ({2} != .Item)\n{1}{{\n{1}\tif ({2} == .Error)\n", inner, body, step);
		e.ReturnBind(scope $"{body}\t\t");
		code.AppendF("{0}\tbreak;\n{0}}}\n", body);
		let valueName = spec.mItem.mType.GetFullName(.. scope .());
		code.AppendF("{}{}* {} = null;\n", body, valueName, valuePtr);
		bool ownsValues = NeedsDelete(spec.mItem);
		let addedKey = e.Local("kp", .. scope .());
		let addedValue = e.Local("ap", .. scope .());
		if (spec.mKeyKind == .String)
		{
			// The key, added before its value is read (the dictionary owns it if reading fails)
			code.AppendF("{0}String {1};\n{0}if ({2}.TryAddAlt(_rd.StringValue, let {5}, let {6}))\n{0}{{\n{0}\t*{5} = {3};\n{0}\t{1} = *{5};\n{0}\t{4} = {6};\n{0}}}\n{0}else\n{0}{{\n{0}\t{1} = *{5};\n{0}\t{4} = {6};\n",
				body, keyText, map, NewExpr("String", .. scope .(), "_rd.StringValue"), valuePtr, addedKey, addedValue);
		}
		else
		{
			let key = e.Local("k", .. scope .());
			code.AppendF("{}{} {} = default;\n", body, keyName, key);
			if (spec.mKeyKind == .Integer)
			{
				let number = e.Local("i", .. scope .());
				if (IsUInt64(spec.mKeyType))
					code.AppendF("{}uint64 {};\n{}if (!JsonBeef.JsonBind.KeyUInt64(_rd, out {}))\n", body, number, body, number);
				else
				{
					let min = scope String();
					let max = scope String();
					IntegerRange(spec.mKeyType, min, max);
					code.AppendF("{}int64 {};\n{}if (!JsonBeef.JsonBind.KeyInteger(_rd, {}, {}, out {}))\n", body, number, body, min, max, number);
				}
				e.ReturnBind(scope $"{body}\t");
				code.AppendF("{}{} = ({}){};\n", body, key, keyName, number);
			}
			else
			{
				let cases = scope String();
				code.AppendF("{}switch (_rd.StringValue)\n{}{{\n", body, body);
				for (let field in spec.mKeyType.GetFields())
				{
					if (!field.IsEnumCase)
						continue;
					let name = ApplyNaming(field.Name, CaseNaming(e), .. scope .());
					if (!cases.IsEmpty)
						cases.Append(", ");
					cases.Append(name);
					code.AppendF("{}case {}: {} = .{};\n", body, AppendLiteral(.. scope .(), name), key, field.Name);
				}
				code.AppendF("{}default:\n", body);
				e.Return(scope $"{body}\t", scope $"JsonBeef.JsonBind.BadKey(_rd, {AppendLiteral(.. scope .(), scope $"one of: {cases}")})");
				code.AppendF("{}}}\n", body);
			}
			// The key's text, for the path of an error in its value
			code.AppendF("{0}let {1} = scope String(_rd.StringValue);\n{0}if ({2}.TryAdd({3}, ?, let {5}))\n{0}\t{4} = {5};\n{0}else\n{0}{{\n{0}\t{4} = {5};\n", body, keyText, map, key, valuePtr, addedValue);
		}
		// A repeated key: an error, or skipped, or read over the earlier value
		code.AppendF("{0}\tswitch (JsonBeef.JsonBind.OnDuplicate(_rd))\n{0}\t{{\n{0}\tcase .Error:\n", body);
		e.ReturnBind(scope $"{body}\t\t");
		code.AppendF("{0}\tcase .Skip:\n{0}\t\tif (!JsonBeef.JsonBind.Value(_rd) || !JsonBeef.JsonBind.Skip(_rd))\n", body);
		e.ReturnBind(scope $"{body}\t\t\t");
		code.AppendF("{0}\t\tcontinue;\n{0}\tcase .Read:\n", body);
		if (ownsValues)
		{
			code.AppendF("{0}\t\tif (_alloc == null)\n{0}\t\t{{\n", body);
			EmitDelete(code, scope $"{body}\t\t\t", spec.mItem, scope $"(*{valuePtr})");
			code.AppendF("{0}\t\t}}\n", body);
		}
		code.AppendF("{0}\t}}\n{0}}}\n{0}*{1} = default;\n{0}if (!JsonBeef.JsonBind.Value(_rd))\n", body, valuePtr);
		e.ReturnBind(scope $"{body}\t");
		e.mPath.Add(new .(false, keyText));
		EmitReadValue(e, body, spec.mItem, "", scope $"*{valuePtr} = {{0}};");
		delete e.mPath.PopBack();
		code.AppendF("{}}}\n{}}}\n", inner, indent);
	}

	/// `new T(args)` from the read's allocator when there is one, else the heap.
	[Comptime]
	static void NewExpr(StringView typeName, String code, StringView args = "")
	{
		code.AppendF("((_alloc != null) ? new:_alloc {0}({1}) : new {0}({1}))", typeName, args);
	}

	/// Whether a value of `spec` owns heap objects to delete when it is replaced (a String, a class, a
	/// List, a Dictionary).
	[Comptime]
	static bool NeedsDelete(ValueSpec spec)
	{
		switch (spec.mKind)
		{
		case .String, .List, .Dictionary:
			return true;
		case .Object, .Converter:
			return !spec.mType.IsValueType;
		default:
			return false;
		}
	}

	/// Deletes the value `expr` (when the object owns it: no allocator) and sets it to null.
	[Comptime]
	static void EmitDeleteOwned(String code, StringView indent, ValueSpec spec, StringView expr)
	{
		code.AppendF("{}if (_alloc == null && {} != null)\n{}{{\n", indent, expr, indent);
		EmitDelete(code, scope $"{indent}\t", spec, expr);
		code.AppendF("{}}}\n", indent);
	}

	/// Deletes `expr` and everything it owns (a List's or Dictionary's items, keys, nested containers).
	[Comptime]
	static void EmitDelete(String code, StringView indent, ValueSpec spec, StringView expr)
	{
		if (!NeedsDelete(spec))
			return;
		if (spec.mKind == .List || spec.mKind == .Dictionary)
			EmitClearItems(code, indent, spec, expr);
		code.AppendF("{}delete {};\n", indent, expr);
	}

	/// Deletes what a List's or Dictionary's items own (not the container itself).
	[Comptime]
	static void EmitClearItems(String code, StringView indent, ValueSpec spec, StringView expr)
	{
		bool ownsKeys = spec.mKind == .Dictionary && spec.mKeyKind == .String;
		bool ownsItems = NeedsDelete(spec.mItem);
		if (!ownsKeys && !ownsItems)
			return;
		let item = scope $"_x{indent.Length}";
		code.AppendF("{}if (_alloc == null)\n{}{{\n{}\tfor (let {} in {})\n{}\t{{\n", indent, indent, indent, item, expr, indent);
		if (spec.mKind == .Dictionary)
		{
			if (ownsKeys)
				code.AppendF("{}\t\tdelete {}.key;\n", indent, item);
			if (ownsItems)
			{
				code.AppendF("{}\t\tif ({}.value != null)\n{}\t\t{{\n", indent, item, indent);
				EmitDelete(code, scope $"{indent}\t\t\t", spec.mItem, scope $"{item}.value");
				code.AppendF("{}\t\t}}\n", indent);
			}
		}
		else
		{
			code.AppendF("{}\t\tif ({} != null)\n{}\t\t{{\n", indent, item, indent);
			EmitDelete(code, scope $"{indent}\t\t\t", spec.mItem, item);
			code.AppendF("{}\t\t}}\n", indent);
		}
		code.AppendF("{}\t}}\n{}}}\n", indent, indent);
	}

	// Writing to a JsonWriter

	[Comptime]
	static void EmitWrite(Emitter e, TypePlan plan, JsonObjectAttribute attribute)
	{
		let code = e.mCode;
		code.Append("\t_w.WriteStartObject();\n");
		if (!plan.mDiscriminator.IsEmpty)
			code.AppendF("\t_w.WritePropertyName({});\n\t_w.WriteString({});\n", AppendLiteral(.. scope .(), plan.mDiscriminator), AppendLiteral(.. scope .(), plan.mTypeName));
		for (let field in plan.mFields)
		{
			let value = scope $"this.{field.mField.Name}";
			let name = AppendLiteral(.. scope .(), field.mName);
			e.mNaming = field.mNaming;
			if (attribute.OmitNulls && CanBeNull(field.mSpec))
			{
				code.AppendF("\tif ({})\n\t{{\n\t\t_w.WritePropertyName({});\n", NotNullExpr(field.mSpec, value, .. scope .()), name);
				EmitWriteValue(e, "\t\t", field.mSpec, value);
				code.Append("\t}\n");
			}
			else
			{
				code.AppendF("\t_w.WritePropertyName({});\n", name);
				EmitWriteValue(e, "\t", field.mSpec, value);
			}
		}
		code.Append("\t_w.WriteEndObject();\n");
	}

	[Comptime]
	static bool CanBeNull(ValueSpec spec)
	{
		return spec.mKind == .Nullable || (!spec.mType.IsValueType && spec.mKind != .Converter);
	}

	[Comptime]
	static void NotNullExpr(ValueSpec spec, StringView value, String expr)
	{
		if (spec.mKind == .Nullable)
			expr.AppendF("{}.HasValue", value);
		else
			expr.AppendF("{} != null", value);
	}

	/// Writes the value `value` (an expression) through `_w`.
	[Comptime]
	static void EmitWriteValue(Emitter e, StringView indent, ValueSpec spec, StringView value)
	{
		let code = e.mCode;
		let inner = scope $"{indent}\t";
		switch (spec.mKind)
		{
		case .Bool:
			code.AppendF("{}_w.WriteBool({});\n", indent, value);
		case .Integer:
			code.AppendF("{}_w.WriteNumber(({}){});\n", indent, IsUInt64(spec.mType) ? "uint64" : (spec.mType.IsSigned || spec.mType.Size < 8) ? "int64" : "uint64", value);
		case .Float:
			if (spec.mType == typeof(float))
				code.AppendF("{}_w.WriteFloat({});\n", indent, value);
			else
				code.AppendF("{}_w.WriteNumber((double){});\n", indent, value);
		case .String:
			code.AppendF("{}JsonBeef.JsonBind.WriteString(_w, {});\n", indent, value);
		case .Enum:
			let typeName = spec.mType.GetFullName(.. scope .());
			if (spec.mEnumNumbers)
			{
				code.AppendF("{}if (", indent);
				EmitIsCase(code, spec.mType, value);
				code.AppendF(")\n{}\t_w.WriteNumber((int64){});\n{}else\n{}\tJsonBeef.JsonBind.InvalidEnum(_w, {}, (int64){});\n", indent, value, indent, indent, AppendLiteral(.. scope .(), typeName), value);
			}
			else
			{
				code.AppendF("{}switch ({})\n{}{{\n", indent, value, indent);
				for (let field in spec.mType.GetFields())
				{
					if (field.IsEnumCase)
						code.AppendF("{}case .{}: _w.WriteString({});\n", indent, field.Name, AppendLiteral(.. scope .(), ApplyNaming(field.Name, CaseNaming(e), .. scope .())));
				}
				code.AppendF("{}default: JsonBeef.JsonBind.InvalidEnum(_w, {}, (int64){});\n{}}}\n", indent, AppendLiteral(.. scope .(), typeName), value, indent);
			}
		case .Converter:
			code.AppendF("{}{}.Write({}, _w);\n", indent, spec.mConverter.GetFullName(.. scope .()), value);
		case .Nullable:
			let local = e.Local("nv", .. scope .());
			code.AppendF("{0}if ({1}.HasValue)\n{0}{{\n{0}\tlet {2} = {1}.Value;\n", indent, value, local);
			EmitWriteValue(e, inner, spec.mItem, local);
			code.AppendF("{0}}}\n{0}else\n{0}\t_w.WriteNull();\n", indent);
		case .Object:
			if (spec.mType.IsValueType)
				code.AppendF("{}{}.JsonWrite(_w);\n", indent, value);
			else
				code.AppendF("{0}if ({1} == null)\n{0}\t_w.WriteNull();\n{0}else\n{0}\t{1}.JsonWrite(_w);\n", indent, value);
		case .List:
			let item = e.Local("e", .. scope .());
			code.AppendF("{0}if ({1} == null)\n{0}\t_w.WriteNull();\n{0}else\n{0}{{\n{0}\t_w.WriteStartArray();\n{0}\tfor (let {2} in {1})\n{0}\t{{\n", indent, value, item);
			EmitWriteValue(e, scope $"{inner}\t", spec.mItem, item);
			code.AppendF("{0}\t}}\n{0}\t_w.WriteEndArray();\n{0}}}\n", indent);
		case .Dictionary:
			let entry = e.Local("kv", .. scope .());
			code.AppendF("{0}if ({1} == null)\n{0}\t_w.WriteNull();\n{0}else\n{0}{{\n{0}\t_w.WriteStartObject();\n{0}\tfor (let {2} in {1})\n{0}\t{{\n", indent, value, entry);
			let body = scope $"{inner}\t";
			let key = e.Local("key", .. scope .());
			EmitKeyText(e, body, spec, scope $"{entry}.key", key, true);
			code.AppendF("{}_w.WritePropertyName({});\n", body, key);
			EmitWriteValue(e, body, spec.mItem, scope $"{entry}.value");
			code.AppendF("{0}\t}}\n{0}\t_w.WriteEndObject();\n{0}}}\n", indent);
		default:
		}
	}

	/// Declares `local` as the member name for the dictionary key `key` (a null String key, or an enum
	/// value that is no case, skips the entry; with `writer`, the latter is a writer error).
	[Comptime]
	static void EmitKeyText(Emitter e, StringView indent, ValueSpec spec, StringView key, StringView local, bool writer)
	{
		let code = e.mCode;
		switch (spec.mKeyKind)
		{
		case .String:
			code.AppendF("{0}if ({1} == null)\n{0}\tcontinue;\n{0}StringView {2} = {1};\n", indent, key, local);
		case .Integer:
			code.AppendF("{}let {} = scope String();\n{}(({}){}).ToString({});\n", indent, local, indent, IsUInt64(spec.mKeyType) ? "uint64" : "int64", key, local);
		default:
			let typeName = spec.mKeyType.GetFullName(.. scope .());
			code.AppendF("{}StringView {};\n{}switch ({})\n{}{{\n", indent, local, indent, key, indent);
			for (let field in spec.mKeyType.GetFields())
			{
				if (field.IsEnumCase)
					code.AppendF("{}case .{}: {} = {};\n", indent, field.Name, local, AppendLiteral(.. scope .(), ApplyNaming(field.Name, CaseNaming(e), .. scope .())));
			}
			if (writer)
				code.AppendF("{0}default:\n{0}\tJsonBeef.JsonBind.InvalidEnum(_w, {1}, (int64){2});\n{0}\tcontinue;\n{0}}}\n", indent, AppendLiteral(.. scope .(), typeName), key);
			else
				code.AppendF("{0}default:\n{0}\treturn .Err(JsonBeef.JsonBind.InvalidEnumError({1}, (int64){2}));\n{0}}}\n", indent, AppendLiteral(.. scope .(), typeName), key);
		}
	}

	/// `value == .A || value == .B …`: whether an enum value is one of its cases.
	[Comptime]
	static void EmitIsCase(String code, Type enumType, StringView value)
	{
		int count = 0;
		for (let field in enumType.GetFields())
		{
			if (!field.IsEnumCase)
				continue;
			if (count++ > 0)
				code.Append(" || ");
			code.AppendF("{} == .{}", value, field.Name);
		}
		if (count == 0)
			code.Append("false");
	}

	// Writing into a JsonNode, in place

	[Comptime]
	static void EmitWriteNode(Emitter e, TypePlan plan, JsonObjectAttribute attribute)
	{
		let code = e.mCode;
		code.Append("\tJsonBeef.JsonBind.MakeObject(_node);\n");
		if (!plan.mDiscriminator.IsEmpty)
			code.AppendF("\tJsonBeef.JsonBind.SetText(_node.Set({}), {});\n", AppendLiteral(.. scope .(), plan.mDiscriminator), AppendLiteral(.. scope .(), plan.mTypeName));
		for (let field in plan.mFields)
		{
			let value = scope $"this.{field.mField.Name}";
			let name = AppendLiteral(.. scope .(), field.mName);
			e.mNaming = field.mNaming;
			for (let alias in field.mAliases)
				code.AppendF("\tJsonBeef.JsonBind.RenameAlias(_node, {}, {});\n", name, AppendLiteral(.. scope .(), alias));
			if (attribute.OmitNulls && CanBeNull(field.mSpec))
			{
				code.AppendF("\tif (!({}))\n\t\t_node.RemoveMember({});\n\telse\n\t{{\n", NotNullExpr(field.mSpec, value, .. scope .()), name);
				code.AppendF("\t\tlet _c = _node.Set({});\n", name);
				EmitWriteNodeValue(e, "\t\t", field.mSpec, value, "_c");
				code.Append("\t}\n");
			}
			else
			{
				code.AppendF("\t{{\n\t\tlet _c = _node.Set({});\n", name);
				EmitWriteNodeValue(e, "\t\t", field.mSpec, value, "_c");
				code.Append("\t}\n");
			}
		}
		code.Append("\treturn .Ok;\n");
	}

	/// Writes `value` into the node `node`: unchanged values left as they are, containers updated in
	/// place (array elements by position, dictionary members by key).
	[Comptime]
	static void EmitWriteNodeValue(Emitter e, StringView indent, ValueSpec spec, StringView value, StringView node)
	{
		let code = e.mCode;
		let inner = scope $"{indent}\t";
		switch (spec.mKind)
		{
		case .Bool:
			code.AppendF("{}JsonBeef.JsonBind.SetBool({}, {});\n", indent, node, value);
		case .Integer:
			if (IsUInt64(spec.mType) || (!spec.mType.IsSigned && spec.mType.Size == 8))
				code.AppendF("{}JsonBeef.JsonBind.SetUInt64({}, (uint64){});\n", indent, node, value);
			else
				code.AppendF("{}JsonBeef.JsonBind.SetInteger({}, (int64){});\n", indent, node, value);
		case .Float:
			if (spec.mType == typeof(float))
				code.AppendF("{}Try!(JsonBeef.JsonBind.SetFloat({}, {}));\n", indent, node, value);
			else
				code.AppendF("{}Try!(JsonBeef.JsonBind.SetDouble({}, (double){}));\n", indent, node, value);
		case .String:
			code.AppendF("{}JsonBeef.JsonBind.SetString({}, {});\n", indent, node, value);
		case .Enum:
			let typeName = spec.mType.GetFullName(.. scope .());
			if (spec.mEnumNumbers)
			{
				code.AppendF("{}if (!(", indent);
				EmitIsCase(code, spec.mType, value);
				code.AppendF("))\n{}\treturn .Err(JsonBeef.JsonBind.InvalidEnumError({}, (int64){}));\n{}JsonBeef.JsonBind.SetInteger({}, (int64){});\n", indent, AppendLiteral(.. scope .(), typeName), value, indent, node, value);
			}
			else
			{
				code.AppendF("{}switch ({})\n{}{{\n", indent, value, indent);
				for (let field in spec.mType.GetFields())
				{
					if (field.IsEnumCase)
						code.AppendF("{}case .{}: JsonBeef.JsonBind.SetText({}, {});\n", indent, field.Name, node, AppendLiteral(.. scope .(), ApplyNaming(field.Name, CaseNaming(e), .. scope .())));
				}
				code.AppendF("{}default: return .Err(JsonBeef.JsonBind.InvalidEnumError({}, (int64){}));\n{}}}\n", indent, AppendLiteral(.. scope .(), typeName), value, indent);
			}
		case .Converter:
			let text = e.Local("ct", .. scope .());
			let writer = e.Local("cw", .. scope .());
			code.AppendF("{0}{{\n{1}let {2} = scope String();\n{1}let {3} = scope JsonBeef.JsonWriter({2});\n{1}{4}.Write({5}, {3});\n{1}Try!({3}.Finish());\n{1}Try!(JsonBeef.JsonBind.SetJson({6}, {2}));\n{0}}}\n",
				indent, inner, text, writer, spec.mConverter.GetFullName(.. scope .()), value, node);
		case .Nullable:
			let local = e.Local("nv", .. scope .());
			code.AppendF("{0}if ({1}.HasValue)\n{0}{{\n{0}\tlet {2} = {1}.Value;\n", indent, value, local);
			EmitWriteNodeValue(e, inner, spec.mItem, local, node);
			code.AppendF("{0}}}\n{0}else\n{0}\tJsonBeef.JsonBind.SetNull({1});\n", indent, node);
		case .Object:
			if (spec.mType.IsValueType)
				code.AppendF("{}Try!({}.JsonWrite({}));\n", indent, value, node);
			else
				code.AppendF("{0}if ({1} == null)\n{0}\tJsonBeef.JsonBind.SetNull({2});\n{0}else\n{0}\tTry!({1}.JsonWrite({2}));\n", indent, value, node);
		case .List:
			let cursor = e.Local("ac", .. scope .());
			let item = e.Local("e", .. scope .());
			let child = e.Local("n", .. scope .());
			code.AppendF("{0}if ({1} == null)\n{0}\tJsonBeef.JsonBind.SetNull({2});\n{0}else\n{0}{{\n{0}\tvar {3} = JsonBeef.JsonArrayCursor({2});\n{0}\tfor (let {4} in {1})\n{0}\t{{\n{0}\t\tlet {5} = {3}.Next();\n",
				indent, value, node, cursor, item, child);
			EmitWriteNodeValue(e, scope $"{inner}\t", spec.mItem, item, child);
			code.AppendF("{0}\t}}\n{0}\t{1}.Trim();\n{0}}}\n", indent, cursor);
		case .Dictionary:
			let members = e.Local("mw", .. scope .());
			let entry = e.Local("kv", .. scope .());
			let child = e.Local("n", .. scope .());
			let key = e.Local("key", .. scope .());
			code.AppendF("{0}if ({1} == null)\n{0}\tJsonBeef.JsonBind.SetNull({2});\n{0}else\n{0}{{\n{0}\tlet {3} = scope JsonBeef.JsonMemberWriter({2});\n{0}\tfor (let {4} in {1})\n{0}\t{{\n",
				indent, value, node, members, entry);
			let body = scope $"{inner}\t";
			EmitKeyText(e, body, spec, scope $"{entry}.key", key, false);
			code.AppendF("{}let {} = {}.Member({});\n", body, child, members, key);
			EmitWriteNodeValue(e, body, spec.mItem, scope $"{entry}.value", child);
			code.AppendF("{0}\t}}\n{0}\t{1}.Finish();\n{0}}}\n", indent, members);
		default:
		}
	}

	// Helpers

	/// Appends `text` as a Beef string literal (control characters as escapes only with `escapeAll`, for
	/// the generated source itself; names cannot hold them).
	[Comptime]
	static void AppendLiteral(String code, StringView text, bool escapeAll = false)
	{
		code.Append('"');
		for (let c in text.RawChars)
		{
			switch (c)
			{
			case '"': code.Append("\\\"");
			case '\\': code.Append("\\\\");
			case '\n': code.Append("\\n");
			case '\t': code.Append("\\t");
			case '\r': code.Append("\\r");
			default:
				if ((uint8)c < 0x20 && !escapeAll)
					Runtime.FatalError(scope $"[JsonObject] \"{text}\" contains a control character");
				code.Append(c);
			}
		}
		code.Append('"');
	}

	/// The smallest and largest value of an integer type below 64 unsigned bits, as int64 source
	/// expressions.
	[Comptime]
	static void IntegerRange(Type type, String min, String max)
	{
		int bits = type.Size * 8;
		if (bits == 64)
		{
			min.Append("int64.MinValue");
			max.Append("int64.MaxValue");
		}
		else if (type.IsSigned)
		{
			min.AppendF("{}", -(1L << (bits - 1)));
			max.AppendF("{}", (1L << (bits - 1)) - 1);
		}
		else
		{
			min.Append("0");
			max.AppendF("{}", (1L << bits) - 1);
		}
	}

	[Comptime]
	static bool IsUInt64(Type type)
	{
		return type.IsInteger && type.Size == 8 && !type.IsSigned;
	}
}
