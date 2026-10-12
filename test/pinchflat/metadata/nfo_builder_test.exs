defmodule Pinchflat.Metadata.NfoBuilderTest do
  use Pinchflat.DataCase

  alias Pinchflat.Metadata.NfoBuilder
  alias Pinchflat.Utils.FilesystemUtils

  setup do
    filepath = FilesystemUtils.generate_metadata_tmpfile(:nfo)

    on_exit(fn -> File.rm!(filepath) end)

    {:ok,
     %{
       metadata: render_parsed_metadata(:media_metadata),
       filepath: filepath
     }}
  end

  describe "build_and_store_for_media_item/2" do
    test "returns the filepath", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)

      assert File.exists?(result)
    end

    test "builds an NFO file", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, ~S(<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>))
      assert String.contains?(nfo, "<title>#{metadata["title"]}</title>")
    end

    test "escapes invalid characters", %{filepath: filepath} do
      metadata = %{
        "title" => "hello' & <world>",
        "uploader" => "uploader",
        "id" => "id",
        "description" => "description",
        "upload_date" => "20210101"
      }

      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "hello&#39; &amp; &lt;world&gt;")
    end

    test "renders the aired date as a plain date with no time or timezone", %{filepath: filepath} do
      metadata = %{
        "title" => "title",
        "uploader" => "uploader",
        "id" => "id",
        "description" => "description",
        "upload_date" => "20210101"
      }

      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "<aired>2021-01-01</aired>")
    end

    test "uses the season and episode number from the filepath if it can be determined" do
      metadata = %{
        "title" => "title",
        "uploader" => "uploader",
        "id" => "id",
        "description" => "description",
        "upload_date" => "20210101"
      }

      tmpfile_directory = Application.get_env(:pinchflat, :tmpfile_directory)
      filepath = Path.join([tmpfile_directory, "foo/s0123e456.nfo"])

      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "<season>0123</season>")
      assert String.contains?(nfo, "<episode>456</episode>")

      File.rm!(filepath)
    end

    test "uses the upload date if the season and episode number can't be determined", %{filepath: filepath} do
      metadata = %{
        "title" => "title",
        "uploader" => "uploader",
        "id" => "id",
        "description" => "description",
        "upload_date" => "20210101"
      }

      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "<season>2021</season>")
      assert String.contains?(nfo, "<episode>0101</episode>")
    end
  end

  describe "build_and_store_for_source/2" do
    test "returns the filepath", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_source(filepath, metadata)

      assert File.exists?(result)
    end

    test "builds an NFO file", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_source(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, ~S(<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>))
      assert String.contains?(nfo, "<title>#{metadata["title"]}</title>")
    end

    test "escapes invalid characters", %{filepath: filepath} do
      metadata = %{
        "title" => "hello' & <world>",
        "description" => "description",
        "id" => "id"
      }

      result = NfoBuilder.build_and_store_for_source(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "hello&#39; &amp; &lt;world&gt;")
    end
  end

  describe "build_and_store_for_media_item/3 with the movie style" do
    setup do
      {:ok,
       %{
         movie_metadata: %{
           "title" => "A Title",
           "description" => "A plot",
           "upload_date" => "20210102",
           "uploader" => "Some Channel",
           "id" => "abc123",
           "categories" => ["Music", "Entertainment"],
           "tags" => ["goth", "synth"]
         }
       }}
    end

    test "writes a full movie NFO", %{movie_metadata: metadata, filepath: filepath} do
      nfo = filepath |> NfoBuilder.build_and_store_for_media_item(metadata, :movie) |> File.read!()

      assert nfo == """
             <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
             <movie>
               <title>A Title</title>
               <plot>A plot</plot>
               <premiered>2021-01-02</premiered>
               <year>2021</year>
               <studio>Some Channel</studio>
               <genre>Music</genre>
               <genre>Entertainment</genre>
               <tag>goth</tag>
               <tag>synth</tag>
               <uniqueid type="youtube" default="true">abc123</uniqueid>
             </movie>
             """
    end

    test "writes no elements for missing categories, tags or uploader", %{movie_metadata: metadata, filepath: filepath} do
      metadata = Map.drop(metadata, ["categories", "uploader"]) |> Map.put("tags", nil)
      nfo = filepath |> NfoBuilder.build_and_store_for_media_item(metadata, :movie) |> File.read!()

      refute nfo =~ "<genre>"
      refute nfo =~ "<tag>"
      refute nfo =~ "<studio>"
      refute nfo =~ "\n\n"
    end

    test "de-duplicates tags case-insensitively, keeping the first spelling", %{
      movie_metadata: metadata,
      filepath: filepath
    } do
      metadata = Map.put(metadata, "tags", ["Goth", "goth", "", "Synth"])
      nfo = filepath |> NfoBuilder.build_and_store_for_media_item(metadata, :movie) |> File.read!()

      assert nfo =~ "<tag>Goth</tag>\n  <tag>Synth</tag>"
      refute nfo =~ "<tag>goth</tag>"
    end

    test "escapes invalid characters", %{movie_metadata: metadata, filepath: filepath} do
      metadata = Map.put(metadata, "title", "Rock & <Roll>")
      nfo = filepath |> NfoBuilder.build_and_store_for_media_item(metadata, :movie) |> File.read!()

      assert nfo =~ "<title>Rock &amp; &lt;Roll&gt;</title>"
    end

    test "does not write an episodedetails document", %{movie_metadata: metadata, filepath: filepath} do
      nfo = filepath |> NfoBuilder.build_and_store_for_media_item(metadata, :movie) |> File.read!()

      refute nfo =~ "episodedetails"
    end
  end
end
