using System;
using System.Collections;
using JsonBeef;

namespace Fixtures;

// Each fixture is built alone by test-codegen.sh, with -define=FIXTURE_<name>. A line
// `// FIXTURE <name>: <text>` gives the text the build error must contain, or OK for a mapping that must
// build (a positive control: the checks must not reject it).

class Program
{
	public static int Main()
	{
		return 0;
	}
}

struct Temperature
{
	public double mCelsius;
}

// FIXTURE OkBaseline: OK
#if FIXTURE_OkBaseline
enum Color { Red, Green }
// (A typealias: Beef's parser stumbles on two closing angle brackets in a skipped #if region)
typealias Row = List<int32>;

[JsonObject(Naming = .CamelCase)]
class Item
{
	public int32 id;
	public uint64 big;
	public String title ~ delete _;
	public Color color;
	public int32? maybe;
	public List<Row> grid ~ DeleteContainerAndItems!(_);
	public Dictionary<String, int32> totals ~ DeleteDictionaryAndKeys!(_);
	public Dictionary<int32, String> byNumber ~ DeleteDictionaryAndValues!(_);
	[JsonName("label"), JsonAlias("caption")] public String name ~ delete _;
	[JsonIgnore] public int32 cache;
	[JsonRequired] public bool flag;
}
#endif

// FIXTURE OkRegisteredConverter: OK
#if FIXTURE_OkRegisteredConverter
// Registered in this project while another project (Other) also depends on JsonBeef: found by the
// mixin-stage lookup (before, through AlwaysVisible, it was not, and the field was "not supported")
[JsonConverter(typeof(Temperature))]
struct TemperatureJson : IJsonConverter<Temperature>
{
	public static Result<void, JsonParseError> Read(JsonReader reader, ref Temperature target)
	{
		target.mCelsius = Try!(reader.GetDouble());
		return .Ok;
	}

	public static void Write(Temperature value, JsonWriter writer)
	{
		writer.WriteNumber(value.mCelsius);
	}
}

[JsonObject]
class Station
{
	public Temperature outside;
	public List<Temperature> history ~ delete _;
}
#endif

// FIXTURE OkPolymorphic: OK
#if FIXTURE_OkPolymorphic
// The subclasses of an abstract base are found in this project too (another project depends on
// JsonBeef): the dispatch is written in the mixin stage, never by a JsonBeef method mixed in
[JsonObject(Discriminator = "kind")]
abstract class Shape
{
	public double x;
}

[JsonObject(TypeName = "circle")]
class Circle : Shape
{
	public double r;
}

[JsonObject(TypeName = "square")]
class Square : Shape
{
	public double side;
}

[JsonObject]
class Drawing
{
	public List<Shape> shapes ~ DeleteContainerAndItems!(_);
}
#endif

// FIXTURE OkSelfReference: OK
#if FIXTURE_OkSelfReference
// A type that holds itself: planned when its methods compile, so no type-initialization cycle
[JsonObject]
class TreeNode
{
	public String name ~ delete _;
	public List<TreeNode> children ~ DeleteContainerAndItems!(_);
}
#endif

// FIXTURE OkGeneric: OK
#if FIXTURE_OkGeneric
// The unspecialized pass gets stub bodies; Box<int32> real ones
[JsonObject]
class Box<T>
{
	public T value;
}

[JsonObject]
class Holder
{
	public Box<int32> boxed ~ delete _;
}
#endif

// FIXTURE Unsupported: JSON serialization does not support fields of type char8
#if FIXTURE_Unsupported
[JsonObject]
class Bad
{
	public char8 letter;
}
#endif

// FIXTURE UnsupportedNested: Fixtures.Bad.nested: JSON serialization does not support fields of type System.Object
#if FIXTURE_UnsupportedNested
// (Typealiases: Beef's parser stumbles on two or three closing angle brackets in a skipped #if region)
typealias Cells = List<Object>;
typealias Inner = List<Cells>;

[JsonObject]
class Bad
{
	public Dictionary<String, Inner> nested;
}
#endif

// FIXTURE DuplicateName: the member "x" is mapped by both Fixtures.Bad.a and Fixtures.Bad.b
#if FIXTURE_DuplicateName
[JsonObject]
class Bad
{
	[JsonName("x")] public int32 a;
	[JsonName("x")] public int32 b;
}
#endif

// FIXTURE DuplicateAlias: the member "old" is mapped by both Fixtures.Bad.a and Fixtures.Bad.b
#if FIXTURE_DuplicateAlias
[JsonObject]
class Bad
{
	[JsonAlias("old")] public int32 a;
	[JsonAlias("old")] public int32 b;
}
#endif

// FIXTURE NamingCollision: the member "pool_size" is mapped by both Fixtures.Bad.poolSize and Fixtures.Bad.PoolSize
#if FIXTURE_NamingCollision
[JsonObject(Naming = .SnakeCase)]
class Bad
{
	public int32 poolSize;
	public int32 PoolSize;
}
#endif

// FIXTURE InheritanceCollision: the member "id" is mapped by both Fixtures.Base.id and Fixtures.Derived.ident
#if FIXTURE_InheritanceCollision
[JsonObject]
class Base
{
	public int32 id;
}

[JsonObject]
class Derived : Base
{
	[JsonName("id")] public int32 ident;
}
#endif

// FIXTURE BadDictionaryKey: dictionary keys must be String, integers or enums
#if FIXTURE_BadDictionaryKey
[JsonObject]
class Bad
{
	public Dictionary<bool, int32> flags;
}
#endif

// FIXTURE TwoConverters: [JsonConverter] Both Fixtures.FirstJson and Fixtures.SecondJson are registered for Fixtures.Temperature
#if FIXTURE_TwoConverters
[JsonConverter(typeof(Temperature))]
struct FirstJson : IJsonConverter<Temperature>
{
	public static Result<void, JsonParseError> Read(JsonReader reader, ref Temperature target) => .Ok;
	public static void Write(Temperature value, JsonWriter writer) => writer.WriteNull();
}

[JsonConverter(typeof(Temperature))]
struct SecondJson : IJsonConverter<Temperature>
{
	public static Result<void, JsonParseError> Read(JsonReader reader, ref Temperature target) => .Ok;
	public static void Write(Temperature value, JsonWriter writer) => writer.WriteNull();
}

[JsonObject]
class Bad
{
	public Temperature t;
}
#endif

// FIXTURE AbstractField: is abstract: reading cannot create one
#if FIXTURE_AbstractField
[JsonObject]
abstract class Animal
{
	public int32 legs;
}

[JsonObject]
class Bad
{
	public Animal pet;
}
#endif

// FIXTURE ControlCharacterName: contains a control character
#if FIXTURE_ControlCharacterName
[JsonObject]
class Bad
{
	[JsonName("a\nb")] public int32 a;
}
#endif

// FIXTURE DiscriminatorOnStruct: a Discriminator needs a class
#if FIXTURE_DiscriminatorOnStruct
[JsonObject(Discriminator = "kind")]
struct Bad
{
	public int32 a;
}
#endif

// FIXTURE DuplicateTypeName: have the type name "same"
#if FIXTURE_DuplicateTypeName
[JsonObject(Discriminator = "kind")]
abstract class Base
{
}

[JsonObject(TypeName = "same")]
class A : Base
{
}

[JsonObject(TypeName = "same")]
class B : Base
{
}

[JsonObject]
class Holder
{
	public Base item;
}
#endif

// FIXTURE NoConcreteSubtype: found no concrete [JsonObject] class for Fixtures.Base
#if FIXTURE_NoConcreteSubtype
[JsonObject(Discriminator = "kind")]
abstract class Base
{
}

[JsonObject]
class Holder
{
	public Base item;
}
#endif
