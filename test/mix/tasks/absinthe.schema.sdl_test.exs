defmodule Mix.Tasks.Absinthe.Schema.SdlTest do
  use Absinthe.Case, async: true

  alias Mix.Tasks.Absinthe.Schema.Sdl, as: Task

  defmodule TestSchema do
    use Absinthe.Schema

    """
    schema {
      query: Query
    }

    type Query {
      helloWorld(name: String!): String
      interfaceField: Being
    }

    interface Being {
      name: String
    }

    type Human implements Being {
      name: String
    }

    type Robot implements Being {
      name: String
    }
    """
    |> import_sdl

    def hydrate(%Absinthe.Blueprint.Schema.InterfaceTypeDefinition{}, _) do
      {:resolve_type, &__MODULE__.resolve_type/1}
    end

    def hydrate(_node, _ancestors), do: []

    def resolve_type(_), do: false
  end

  @test_schema "Mix.Tasks.Absinthe.Schema.SdlTest.TestSchema"

  defmodule TestModField do
    use Absinthe.Schema.Notation

    object :test_mod_helper do
      description "Simple Helper Object used to define blueprint fields"

      field :mod_field, :string do
        description "extra field added by schema modification"
      end
    end
  end

  defmodule TestModifier do
    alias Absinthe.{Phase, Pipeline, Blueprint}

    # Add this module to the pipeline of phases
    # to run on the schema
    def pipeline(pipeline) do
      Pipeline.insert_after(pipeline, Phase.Schema.TypeImports, __MODULE__)
    end

    # Here's the blueprint of the schema, let's do whatever we want with it.
    def run(blueprint = %Blueprint{}, _) do
      test_mod_types = Blueprint.types_by_name(TestModField)
      test_mod_fields = test_mod_types["TestModHelper"]

      mod_field = Blueprint.find_field(test_mod_fields, "mod_field")

      blueprint = Blueprint.add_field(blueprint, "Mod", mod_field)

      {:ok, blueprint}
    end
  end

  defmodule TestSchemaWithMods do
    use Absinthe.Schema

    @pipeline_modifier TestModifier

    query do
      field :hello_world, :mod do
        arg :name, non_null(:string)
      end

      field :interface_field, :being
    end

    object :mod do
    end

    interface :being do
      field :name, :string
      resolve_type(fn obj, _ -> obj.type end)
    end

    object :human do
      interface :being
      field :name, :string
    end

    object :robot do
      interface :being
      field :name, :string
    end
  end

  defmodule TestSchemaWithDefaults do
    use Absinthe.Schema

    query do
      field :string, :string, default_value: "string_default"
      field :integer, :integer, default_value: 2137
      field :float, :float, default_value: 3.14
      field :id, :id, default_value: 1
      field :boolean, :boolean, default_value: true
      # TODO Add support for compound types
      field :non_null_boolean, non_null(:boolean), default_value: true
      field :enum, non_null(:enum), default_value: "SECOND"

      field :compound_boolean, :boolean, default_value: false do
        arg :string, :string, default_value: "argument_string_default"
        arg :integer, :integer, default_value: 12137
        arg :float, :float, default_value: 13.14
        arg :id, :id, default_value: 11
        arg :boolean, :boolean, default_value: false
        arg :non_null_boolean, non_null(:boolean), default_value: false
        # This enum still needs to print FIRST as a default, since it's only an alias
        # TODO Add support for compound types
        arg :enum, non_null(:enum), default_value: "FiRsT  x"
        arg :input_object, :input_object, default_value: %{string: "Hey!"}
      end
    end

    enum :enum do
      value :first, as: "FiRsT  x"
      value :second, as: "SECOND"
    end

    input_object :input_object do
      field :string, :string, default_value: "string_default"
    end
  end

  defmodule PersistentTermTestSchema do
    use Absinthe.Schema

    @schema_provider Absinthe.Schema.PersistentTerm

    query do
      field :item, :item
    end

    object :item do
      description "A Basic Type"
      field :id, :id
      field :name, :string
    end
  end

  @test_mod_schema "Mix.Tasks.Absinthe.Schema.SdlTest.TestSchemaWithMods"

  setup_all do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)
    on_exit(fn -> Mix.shell(shell) end)
  end

  describe "absinthe.schema.sdl" do
    test "parses options" do
      argv = ["output.graphql", "--schema", @test_schema]

      opts = Task.parse_options(argv)

      assert opts.filename == "output.graphql"
      assert opts.schema == TestSchema
    end

    test "provides default options" do
      argv = ["--schema", @test_schema]

      opts = Task.parse_options(argv)

      assert opts.filename == "./schema.graphql"
      assert opts.schema == TestSchema
    end

    test "fails if no schema arg is provided" do
      argv = []
      catch_error(Task.parse_options(argv))
    end

    test "Generate schema" do
      argv = ["--schema", @test_schema]
      opts = Task.parse_options(argv)

      {:ok, schema} = Task.generate_schema(opts)
      assert schema =~ "helloWorld(name: String!): String"
    end

    test "Generate schema with modifier" do
      argv = ["--schema", @test_mod_schema]
      opts = Task.parse_options(argv)

      {:ok, schema} = Task.generate_schema(opts)

      assert schema =~ "type Mod {"
      assert schema =~ "modField: String"
      assert schema =~ "type Robot implements Being"
    end

    @tag :tmp_dir
    test "generates an SDL file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "schema.sdl")

      argv = ["--schema", @test_schema, path]
      assert Task.run(argv)

      assert File.exists?(path)
    end

    @tag :tmp_dir
    test "generates an SDL file for a persistent term schema provider", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "schema.sdl")

      argv = ["--schema", "#{PersistentTermTestSchema}", path]
      assert Task.run(argv)

      assert File.exists?(path)
    end
  end

  @schema_with_defaults "Mix.Tasks.Absinthe.Schema.SdlTest.TestSchemaWithDefaults"
  test "default values are set correctly" do
    argv = ["--schema", @schema_with_defaults]
    opts = Task.parse_options(argv)

    {:ok, schema} = Task.generate_schema(opts)
    # Field defaults work
    assert schema =~ "string: String = \"string_default\""
    assert schema =~ "integer: Int = 2137"
    assert schema =~ "float: Float = 3.14"
    assert schema =~ "id: ID = \"1\""
    assert schema =~ "boolean: Boolean = true"
    assert schema =~ "nonNullBoolean: Boolean! = true"

    # Argument defaults work
  end
end
