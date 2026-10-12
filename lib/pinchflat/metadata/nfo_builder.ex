defmodule Pinchflat.Metadata.NfoBuilder do
  @moduledoc """
  Provides methods for building and storing NFO files for
  use by Kodi/Jellyfin and other media center software.
  """

  import Pinchflat.Utils.XmlUtils, only: [safe: 1]

  alias Pinchflat.Utils.FilesystemUtils
  alias Pinchflat.Metadata.MetadataFileHelpers

  @doc """
  Builds an NFO file for a media item (read: single "episode") and
  stores it at the specified location.

  The style is `:episode` (an `<episodedetails>` file, the default) or
  `:movie` (a `<movie>` file, for libraries of standalone videos).

  Returns the filepath of the NFO file.
  """
  def build_and_store_for_media_item(nfo_filepath, metadata, style \\ :episode) do
    nfo =
      case style do
        :movie -> build_movie_for_media_item(metadata)
        _ -> build_for_media_item(nfo_filepath, metadata)
      end

    FilesystemUtils.write_p!(nfo_filepath, nfo)

    nfo_filepath
  end

  @doc """
  Builds an NFO file for a souce and stores it at the specified location.
  Technically works for playlists, but it's really made for channels.

  Returns the filepath of the NFO file.
  """
  def build_and_store_for_source(filepath, metadata) do
    nfo = build_for_source(metadata)

    FilesystemUtils.write_p!(filepath, nfo)

    filepath
  end

  defp build_for_media_item(nfo_filepath, metadata) do
    upload_date = MetadataFileHelpers.parse_upload_date(metadata["upload_date"])
    # NOTE: the filepath here isn't the path of the media item, it's the path that
    # the NFO should be saved to. This works because the NFO's path is the same as
    # the media's path, just with a different extension. If this ever changes I'll
    # need to pass in the media item's path as well.
    {season, episode} = determine_season_and_episode_number(nfo_filepath, upload_date)

    # Cribbed from a combination of the Kodi wiki, ytdl-nfo, and ytdl-sub.
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
    <episodedetails>
      <title>#{safe(metadata["title"])}</title>
      <showtitle>#{safe(metadata["uploader"])}</showtitle>
      <uniqueid type="youtube" default="true">#{safe(metadata["id"])}</uniqueid>
      <plot>#{safe(metadata["description"])}</plot>
      <aired>#{safe(DateTime.to_date(upload_date))}</aired>
      <season>#{safe(season)}</season>
      <episode>#{episode}</episode>
      <genre>YouTube</genre>
    </episodedetails>
    """
  end

  defp build_movie_for_media_item(metadata) do
    upload_date = MetadataFileHelpers.parse_upload_date(metadata["upload_date"])

    # Optional elements are built as a list so an empty one leaves no blank line
    lines =
      [
        "<title>#{safe(metadata["title"])}</title>",
        "<plot>#{safe(metadata["description"])}</plot>",
        "<premiered>#{safe(DateTime.to_date(upload_date))}</premiered>",
        "<year>#{safe(upload_date.year)}</year>"
      ] ++
        studio_lines(metadata["uploader"]) ++
        list_lines("genre", metadata["categories"]) ++
        list_lines("tag", metadata["tags"]) ++
        [~s(<uniqueid type="youtube" default="true">#{safe(metadata["id"])}</uniqueid>)]

    body = Enum.map_join(lines, "\n", &("  " <> &1))

    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
    <movie>
    #{body}
    </movie>
    """
  end

  defp studio_lines(uploader) when is_binary(uploader) and uploader != "", do: ["<studio>#{safe(uploader)}</studio>"]
  defp studio_lines(_), do: []

  # Drops blanks and case-insensitive duplicates, keeping the first spelling and the order
  defp list_lines(element, values) when is_list(values) do
    values
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.map(&"<#{element}>#{safe(&1)}</#{element}>")
  end

  defp list_lines(_element, _values), do: []

  defp build_for_source(metadata) do
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
    <tvshow>
      <title>#{safe(metadata["title"])}</title>
      <plot>#{safe(metadata["description"])}</plot>
      <uniqueid type="youtube" default="true">#{safe(metadata["id"])}</uniqueid>
      <genre>YouTube</genre>
    </tvshow>
    """
  end

  defp determine_season_and_episode_number(filepath, upload_date) do
    case MetadataFileHelpers.season_and_episode_from_media_filepath(filepath) do
      {:ok, {season, episode}} -> {season, episode}
      {:error, _} -> {upload_date.year, Calendar.strftime(upload_date, "%m%d")}
    end
  end
end
