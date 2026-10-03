using System;
using System.Collections;
using System.Reflection;
using FormatCore.Mapping;
using internal FormatCore;

namespace JsonBeef;

/// The planning half of the generator: what each value is (FormatCore's ValueSpec, recursively through
/// Lists, Dictionaries and `T?`), the members a type's [JsonObject] chain maps and the conflicts between
/// them, all checked before JsonSerializerCodeGen.bf writes any code. Runs in the mixin stage (bodies
/// through FormatCore's MappingDriver), so converter and subtype lookups (FormatCore's Registry) see the
/// user's project and what it depends on, however many projects depend on JsonBeef.
extension JsonSerializerCodeGen
{
	/// One member a field maps: its names (raw text), its value, its slot (the bit that notes it was read).
	class FieldPlan
	{
		public FieldInfo mField;
		public String mName = new .() ~ delete _;
		public List<String> mAliases = new .() ~ DeleteContainerAndItems!(_);
		public bool mRequired;
		public ValueSpec mSpec ~ delete _;
		public int mSlot;
		/// The naming of the field's level (its enum case names follow it).
		public JsonNaming mNaming;

		public this()
		{
		}
	}

	/// The whole chain's plan: fields from the base-most [JsonObject] level down, the discriminator.
	class TypePlan
	{
		public List<FieldPlan> mFields = new .() ~ DeleteContainerAndItems!(_);
		/// The discriminator's member name (empty: none) and this type's value of it.
		public String mDiscriminator = new .() ~ delete _;
		public String mTypeName = new .() ~ delete _;
		/// The discriminator's slot (the first), or -1.
		public int mDiscriminatorSlot = -1;
		public int mSlots;

		public this()
		{
		}
	}

	/// Plans every serialized field of `type` and its [JsonObject] bases, stopping the build for a field
	/// that cannot be mapped or two members of one name.
	[Comptime]
	static TypePlan PlanType(Type type, JsonObjectAttribute attribute, StringView ownerName)
	{
		let plan = new TypePlan();
		// The discriminator: this type's or the nearest base's
		for (Type level = type; level != null && !level.IsValueType; level = level.BaseType)
		{
			if (level.GetCustomAttribute<JsonObjectAttribute>() case .Ok(let levelAttribute) && levelAttribute.Discriminator != null)
			{
				plan.mDiscriminator.Set(levelAttribute.Discriminator);
				break;
			}
		}
		if (type.IsValueType && attribute.Discriminator != null)
			FailType(ownerName, "a Discriminator needs a class: structs have no subtypes");
		if (!plan.mDiscriminator.IsEmpty)
		{
			TypeNameOf(type, plan.mTypeName);
			plan.mDiscriminatorSlot = plan.mSlots++;
		}

		// The levels, base-most first
		let levels = scope List<Type>();
		for (Type level = type; level != null && level.HasCustomAttribute<JsonObjectAttribute>(); level = level.IsValueType ? null : level.BaseType)
			levels.Insert(0, level);
		// The member names taken, and by which field (for the conflict message)
		let taken = scope Dictionary<String, String>();
		defer
		{
			for (let entry in taken)
			{
				delete entry.key;
				delete entry.value;
			}
		}
		if (!plan.mDiscriminator.IsEmpty)
			taken[new .(plan.mDiscriminator)] = new .("the discriminator");
		for (let level in levels)
		{
			var levelAttribute = attribute;
			if (level != type && level.GetCustomAttribute<JsonObjectAttribute>() case .Ok(let own))
				levelAttribute = own;
			for (let field in level.GetFields())
			{
				if (!IsSerialized(level, field))
					continue;
				let fieldPath = scope $"{level.GetFullName(.. scope .())}.{field.Name}";
				let fieldPlan = PlanField(field, levelAttribute, ownerName);
				fieldPlan.mSlot = plan.mSlots++;
				plan.mFields.Add(fieldPlan);
				let names = scope List<StringView>();
				names.Add(fieldPlan.mName);
				for (let alias in fieldPlan.mAliases)
					names.Add(alias);
				for (let name in names)
				{
					CheckName(ownerName, field.Name, name);
					if (taken.TryGetValue(scope String(name), let other))
						FailType(ownerName, scope $"the member \"{name}\" is mapped by both {other} and {fieldPath} (names come from [JsonName], [JsonAlias] or the field's name through the Naming)");
					taken[new .(name)] = new .(fieldPath);
				}
			}
		}
		return plan;
	}

	[Comptime]
	static FieldPlan PlanField(FieldInfo field, JsonObjectAttribute attribute, StringView ownerName)
	{
		let plan = new FieldPlan();
		plan.mField = field;
		plan.mNaming = attribute.Naming;
		if (field.GetCustomAttribute<JsonNameAttribute>() case .Ok(let named))
			plan.mName.Set(named.mName);
		else
			Naming.Apply(field.Name, attribute.Naming, plan.mName);
		for (let alias in field.GetCustomAttributes<JsonAliasAttribute>())
			plan.mAliases.Add(new .(alias.mName));
		plan.mRequired = field.HasCustomAttribute<JsonRequiredAttribute>();
		Type useConverter = null;
		if (field.GetCustomAttribute<JsonUseConverterAttribute>() case .Ok(let use))
			useConverter = use.mConverter;
		plan.mSpec = Spec(field.FieldType, useConverter, attribute, ownerName, field.Name);
		return plan;
	}

	/// The spec of a value of `type`; a converter given for the field applies to the innermost value.
	[Comptime]
	static ValueSpec Spec(Type type, Type useConverter, JsonObjectAttribute attribute, StringView ownerName, StringView fieldName)
	{
		let spec = new ValueSpec();
		spec.mType = type;
		spec.mEnumNumbers = attribute.EnumsAsNumbers;
		Type item = null;
		if ((item = TypeShapes.ListElement(type)) != null)
		{
			spec.mKind = .List;
			spec.mItem = Spec(item, useConverter, attribute, ownerName, fieldName);
			return spec;
		}
		if ((item = TypeShapes.DictionaryValue(type)) != null)
		{
			spec.mKind = .Dictionary;
			spec.mKeyType = TypeShapes.DictionaryKey(type);
			spec.mKeyKind = TypeShapes.KeyKind(spec.mKeyType);
			if (spec.mKeyKind == .Unsupported)
				Fail(ownerName, fieldName, scope $"dictionary keys must be String, integers or enums (JSON member names are text), not {spec.mKeyType.GetFullName(.. scope .())}");
			spec.mItem = Spec(item, useConverter, attribute, ownerName, fieldName);
			return spec;
		}
		if ((item = TypeShapes.NullableValue(type)) != null)
		{
			spec.mKind = .Nullable;
			spec.mItem = Spec(item, useConverter, attribute, ownerName, fieldName);
			if (!spec.mItem.mType.IsValueType)
				Fail(ownerName, fieldName, "Nullable needs a value type");
			return spec;
		}
		if (useConverter != null)
		{
			spec.mKind = .Converter;
			spec.mConverter = useConverter;
			return spec;
		}
		spec.mKind = Classify(type, out spec.mConverter);
		switch (spec.mKind)
		{
		case .Unsupported:
			let typeName = type.GetFullName(.. scope .());
			Fail(ownerName, fieldName, scope $"JSON serialization does not support fields of type {typeName}. Supported: bool, integers, float, double, String, enums, [JsonObject] types, T? of those, Lists and Dictionaries (String, integer or enum keys) of any of these; also types with a converter ([JsonConverter] registration or [JsonUseConverter] on the field). Mark the field [JsonIgnore] to leave it out.");
		case .Object:
			if (!type.IsValueType)
			{
				spec.mPolymorphic = HasDiscriminator(type);
				if (!spec.mPolymorphic && type.IsAbstract)
					Fail(ownerName, fieldName, scope $"{type.GetFullName(.. scope .())} is abstract: reading cannot create one. Give it a Discriminator ([JsonObject(Discriminator = \"kind\")]) so that its subtypes are read, or use a converter");
			}
		default:
		}
		return spec;
	}

	[Comptime]
	static bool IsSerialized(Type type, FieldInfo field)
	{
		return field.DeclaringType == type && !field.IsStatic && !field.IsConst && field.IsPublic && !field.HasCustomAttribute<JsonIgnoreAttribute>();
	}

	[Comptime]
	static void Fail(StringView ownerName, StringView fieldName, StringView message)
	{
		MappingError.Fail("[JsonObject]", ownerName, fieldName, message);
	}

	/// A mapping error about the type as a whole: `message` names the fields (with their declaring types).
	[Comptime]
	static void FailType(StringView ownerName, StringView message)
	{
		MappingError.FailType("[JsonObject]", ownerName, message);
	}

	/// Member names may be any text but control characters (a Beef string literal holds them).
	[Comptime]
	static void CheckName(StringView ownerName, StringView fieldName, StringView name)
	{
		for (let c in name.RawChars)
		{
			if ((uint8)c < 0x20)
				Fail(ownerName, fieldName, scope $"the name \"{name}\" contains a control character");
		}
	}

	/// How a value of `type` is handled (not a List, Dictionary or Nullable: Spec takes those first).
	[Comptime]
	static ValueKind Classify(Type type, out Type converter)
	{
		converter = null;
		let scalar = TypeShapes.ScalarKind(type);
		if (scalar != .Unsupported)
			return scalar;
		if (type == typeof(char8) || type == typeof(char16) || type == typeof(char32))
			return .Unsupported;
		converter = FindRegisteredConverter(type);
		if (converter != null)
			return .Converter;
		// Simple enums only: cases with payloads have no single name to write
		if (type.IsEnum && !type.IsUnion)
			return .Enum;
		if (type.HasCustomAttribute<JsonObjectAttribute>() || (!type.IsInterface && type.ImplementsInterface(typeof(IJsonSerializable))))
			return .Object;
		return .Unsupported;
	}

	/// Whether a class or one of its bases has a Discriminator.
	[Comptime]
	static bool HasDiscriminator(Type type)
	{
		for (Type level = type; level != null && !level.IsValueType; level = level.BaseType)
		{
			if (level.GetCustomAttribute<JsonObjectAttribute>() case .Ok(let attribute) && attribute.Discriminator != null)
				return true;
		}
		return false;
	}

	/// The discriminator's member name for a class (its own or the nearest base's).
	[Comptime]
	static void DiscriminatorOf(Type type, String name)
	{
		for (Type level = type; level != null && !level.IsValueType; level = level.BaseType)
		{
			if (level.GetCustomAttribute<JsonObjectAttribute>() case .Ok(let attribute) && attribute.Discriminator != null)
			{
				name.Append(attribute.Discriminator);
				return;
			}
		}
	}

	/// A [JsonObject] class's value of the discriminator: its TypeName, or its name through its Naming.
	[Comptime]
	static void TypeNameOf(Type type, String name)
	{
		if (type.GetCustomAttribute<JsonObjectAttribute>() case .Ok(let attribute))
		{
			if (attribute.TypeName != null)
				name.Append(attribute.TypeName);
			else
				Naming.Apply(type.GetName(.. scope .()), attribute.Naming, name);
		}
		else
			name.Append(type.GetName(.. scope .()));
	}

	/// The [JsonObject] classes a field of class `type` with a discriminator can hold: `type` itself
	/// unless abstract, and every concrete [JsonObject] class deriving from it that the user's project
	/// can see (Registry.IsVisible: only valid in the mixin stage, which is where bodies are planned).
	[Comptime]
	static void SubTypes(Type type, List<Type> types)
	{
		if (!type.IsAbstract && type.HasCustomAttribute<JsonObjectAttribute>())
			types.Add(type);
		for (let declaration in Type.TypeDeclarations)
		{
			if (!Registry.IsVisible(declaration))
				continue;
			if (!declaration.HasCustomAttribute<JsonObjectAttribute>())
				continue;
			let candidate = declaration.ResolvedType;
			if (candidate == null || candidate == type || candidate.IsValueType || candidate.IsInterface || candidate.IsAbstract || candidate.IsGenericParam)
				continue;
			if (candidate.IsSubtypeOf(type))
				types.Add(candidate);
		}
	}

	/// The converter registered with [JsonConverter(typeof(target))] that the user's project can see, or
	/// null (Registry.IsVisible, in the mixin stage: the AlwaysVisible test it replaces lost the user's
	/// converters once a second project depended on JsonBeef). Two such registrations stop the build.
	[Comptime]
	static Type FindRegisteredConverter(Type target)
	{
		Type found = null;
		for (let declaration in Type.TypeDeclarations)
		{
			if (!Registry.IsVisible(declaration))
				continue;
			if (!(declaration.GetCustomAttribute<JsonConverterAttribute>() case .Ok(let registration)) || registration.mTarget != target)
				continue;
			let converter = declaration.ResolvedType;
			if (found != null && found != converter)
			{
				// Named in a stable order (declarations come in no fixed order)
				let a = found.GetFullName(.. scope .());
				let b = converter.GetFullName(.. scope .());
				bool inOrder = String.Compare(a, b, false) <= 0;
				Runtime.FatalError(scope $"[JsonConverter] Both {inOrder ? a : b} and {inOrder ? b : a} are registered for {target.GetFullName(.. scope .())}. Keep one, or pick one per field with [JsonUseConverter].");
			}
			found = converter;
		}
		return found;
	}
}
