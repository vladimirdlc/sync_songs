# -*- coding: utf-8 -*-

require 'lastfm'
require_relative '../song_set'

# Public: Classes for syncing sets of songs.
module SyncSongs
  # Public: A set of Grooveshark songs.
  class LastfmSet < SongSet
    # Public: Hash of types of services associated with what they support.
    SERVICES = {loved: :rw, favorites: :rw}
    # Public: Default limit for API calls.
    DEFAULT_LIMIT = 1_000_000

    # Public: Constructs a Last.fm set by logging in to
    # Last.fm with the specified user.
    #
    # api_key    - Last.fm API key.
    # api_secret - Last.fm secret for API key.
    # username   - The username of the Last.fm user.
    # limit      - The maximum number of results from calls (default:
    #              DEFAULT_LIMIT).
    def initialize(api_key, api_secret, username = nil, limit = DEFAULT_LIMIT)
      super()
      @api_key = api_key
      @username = username
      @lastfm = Lastfm.new(api_key, api_secret)
      @limit = limit
    end

    # Public: Get the user's loved songs from Last.fm.
    #
    # username - The username of the user to authenticate (default:
    #            @username).
    #
    # limit    - The maximum number of favorites to get (default:
    #            @limit).
    #
    # Raises Lastfm::ApiError if the username is invalid or there is a
    # temporary error.
    #
    # Returns self.
    def loved(username = @username, limit = @limit)
      @lastfm.user.get_loved_tracks(user: username,
                                    api_key: @api_key,
                                    limit: limit).each do |l|

        # Get metadata for loved track.
        s = @lastfm.track.get_info(track: l['name'],
                                   artist: l['artist']['name'])

        add(Song.new(s['name'], s['artist']['name'],
                     # Not all Last.fm tracks belong to an album.
                     s.key?('album') ? s['album']['title'] : nil))
      end

      self
    end

    alias_method :favorites, :loved

    # Public: Add the songs in the given set to the given user's loved
    # songs on Last.fm. This method requires an authorized session
    # which is gotten by getting the user to authorize via the url
    # given by authorizeURL and then running authorize.
    #
    # other - A SongSet to add from.
    #
    # Raises Lastfm::ApiError if the Last.fm token has not been
    #   authorized or if the song is not recognized.
    #
    # Returns an array of the songs that was added.
    def addToLoved(other)
      songsAdded = []

      if @lastfm.session
        other.each { |song| songsAdded << song if @lastfm.track.love(track: song.name, artist: song.artist) }
      end

      songsAdded
    end

    alias_method :addToFavorites, :addToLoved

    # Public: Searches for the given song set at Last.fm.
    #
    #
    # other         - SongSet to search for.
    # limit         - Maximum limit for search results (default:
    #                 @limit).
    # strict_search - True if search should be strict (default: true).
    #
    # Returns a SongSet.
    def search(other, limit = @limit, strict_search = true)
      result = SongSet.new

      # Search for songs that are not already in this set and return
      # them if they are sufficiently similar.
      exclusiveTo(other).each do |song|
        # The optional parameter artist for track.search does not seem
        # to work so it is not used.
        search_result = @lastfm.track.search(track: song.to_search_term,
                                      limit: limit)['results']['trackmatches']['track'].compact

        found_songs = []

        search_result.each do |r|
          found_songs << @lastfm.track.get_info(track: r['name'],
                                                artist: r['artist'])
        end

        unless found_songs.empty?
          found_songs.each do |f|
            other = Song.new(f['name'], f['artist']['name'],
                              f.key?('album') ? f['album']['title'] : nil,
                              Float(f['duration']) / 1_000)
            if strict_search
              next unless song.eql?(other)
            else
              next unless song.similar?(other)
            end
            result << other
          end
        end
      end
      result
    end

    # Public: Return an URL for authorizing a Last.fm session.
    def authorizeURL
      @token = @lastfm.auth.get_token
      "http://www.last.fm/api/auth/?api_key=#@api_key&token=#@token"
    end


    # Public: Authorize a Last.fm session (needed for certain calls to
    # Last.fm, such as addToLoved). Get the user to authorize via the
    # URL returned by authorizeURL before calling this method.
    def authorize
      if @token
        @lastfm.session = @lastfm.auth.get_session(token: @token)['key']
      else
        fail StandardError, "Before calling #{__method__} a token must be authorized, e.g. by calling authorizeURL and getting the user to authorize via that URL."
      end
    end
  end
end