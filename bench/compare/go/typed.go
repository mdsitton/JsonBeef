// The typed track's structures (see ../reference.py for the schema and its simplifications of
// serde-rs/json-benchmark's src/copy/twitter.rs, citm_catalog.rs and canada.rs), shared by every Go
// library: each one decodes into these through the encoding/json struct tags. Also the partial
// structures of the query track's json-partial variant.
package main

import (
	"fmt"
	"unicode/utf8"
)

// ---- twitter ----

type Twitter struct {
	Statuses       []Status       `json:"statuses"`
	SearchMetadata SearchMetadata `json:"search_metadata"`
}

type Status struct {
	Metadata             Metadata       `json:"metadata"`
	CreatedAt            string         `json:"created_at"`
	ID                   uint64         `json:"id"`
	IDStr                string         `json:"id_str"`
	Text                 string         `json:"text"`
	Source               string         `json:"source"`
	Truncated            bool           `json:"truncated"`
	InReplyToStatusID    *uint64        `json:"in_reply_to_status_id"`
	InReplyToStatusIDStr *string        `json:"in_reply_to_status_id_str"`
	InReplyToUserID      *uint32        `json:"in_reply_to_user_id"`
	InReplyToUserIDStr   *string        `json:"in_reply_to_user_id_str"`
	InReplyToScreenName  *string        `json:"in_reply_to_screen_name"`
	User                 User           `json:"user"`
	Geo                  *string        `json:"geo"`
	Coordinates          *string        `json:"coordinates"`
	Place                *string        `json:"place"`
	Contributors         *string        `json:"contributors"`
	RetweetedStatus      *Status        `json:"retweeted_status"`
	RetweetCount         uint32         `json:"retweet_count"`
	FavoriteCount        uint32         `json:"favorite_count"`
	Entities             StatusEntities `json:"entities"`
	Favorited            bool           `json:"favorited"`
	Retweeted            bool           `json:"retweeted"`
	PossiblySensitive    *bool          `json:"possibly_sensitive"`
	Lang                 string         `json:"lang"`
}

type Metadata struct {
	ResultType      string `json:"result_type"`
	IsoLanguageCode string `json:"iso_language_code"`
}

type User struct {
	ID                             uint32       `json:"id"`
	IDStr                          string       `json:"id_str"`
	Name                           string       `json:"name"`
	ScreenName                     string       `json:"screen_name"`
	Location                       string       `json:"location"`
	Description                    string       `json:"description"`
	URL                            *string      `json:"url"`
	Entities                       UserEntities `json:"entities"`
	Protected                      bool         `json:"protected"`
	FollowersCount                 uint32       `json:"followers_count"`
	FriendsCount                   uint32       `json:"friends_count"`
	ListedCount                    uint32       `json:"listed_count"`
	CreatedAt                      string       `json:"created_at"`
	FavouritesCount                uint32       `json:"favourites_count"`
	UtcOffset                      *int32       `json:"utc_offset"`
	TimeZone                       *string      `json:"time_zone"`
	GeoEnabled                     bool         `json:"geo_enabled"`
	Verified                       bool         `json:"verified"`
	StatusesCount                  uint32       `json:"statuses_count"`
	Lang                           string       `json:"lang"`
	ContributorsEnabled            bool         `json:"contributors_enabled"`
	IsTranslator                   bool         `json:"is_translator"`
	IsTranslationEnabled           bool         `json:"is_translation_enabled"`
	ProfileBackgroundColor         string       `json:"profile_background_color"`
	ProfileBackgroundImageURL      string       `json:"profile_background_image_url"`
	ProfileBackgroundImageURLHTTPS string       `json:"profile_background_image_url_https"`
	ProfileBackgroundTile          bool         `json:"profile_background_tile"`
	ProfileImageURL                string       `json:"profile_image_url"`
	ProfileImageURLHTTPS           string       `json:"profile_image_url_https"`
	ProfileBannerURL               *string      `json:"profile_banner_url"`
	ProfileLinkColor               string       `json:"profile_link_color"`
	ProfileSidebarBorderColor      string       `json:"profile_sidebar_border_color"`
	ProfileSidebarFillColor        string       `json:"profile_sidebar_fill_color"`
	ProfileTextColor               string       `json:"profile_text_color"`
	ProfileUseBackgroundImage      bool         `json:"profile_use_background_image"`
	DefaultProfile                 bool         `json:"default_profile"`
	DefaultProfileImage            bool         `json:"default_profile_image"`
	Following                      bool         `json:"following"`
	FollowRequestSent              bool         `json:"follow_request_sent"`
	Notifications                  bool         `json:"notifications"`
}

type UserEntities struct {
	URL         *UserURL        `json:"url"`
	Description UserDescription `json:"description"`
}

type UserURL struct {
	Urls []URL `json:"urls"`
}

type UserDescription struct {
	Urls []URL `json:"urls"`
}

type URL struct {
	URL         string `json:"url"`
	ExpandedURL string `json:"expanded_url"`
	DisplayURL  string `json:"display_url"`
	Indices     []int  `json:"indices"`
}

type StatusEntities struct {
	Hashtags     []Hashtag     `json:"hashtags"`
	Symbols      []string      `json:"symbols"`
	Urls         []URL         `json:"urls"`
	UserMentions []UserMention `json:"user_mentions"`
	Media        []Media       `json:"media"`
}

type Hashtag struct {
	Text    string `json:"text"`
	Indices []int  `json:"indices"`
}

type UserMention struct {
	ScreenName string `json:"screen_name"`
	Name       string `json:"name"`
	ID         uint32 `json:"id"`
	IDStr      string `json:"id_str"`
	Indices    []int  `json:"indices"`
}

type Media struct {
	ID                uint64  `json:"id"`
	IDStr             string  `json:"id_str"`
	Indices           []int   `json:"indices"`
	MediaURL          string  `json:"media_url"`
	MediaURLHTTPS     string  `json:"media_url_https"`
	URL               string  `json:"url"`
	DisplayURL        string  `json:"display_url"`
	ExpandedURL       string  `json:"expanded_url"`
	Type              string  `json:"type"`
	Sizes             Sizes   `json:"sizes"`
	SourceStatusID    *uint64 `json:"source_status_id"`
	SourceStatusIDStr *string `json:"source_status_id_str"`
}

type Sizes struct {
	Medium Size `json:"medium"`
	Small  Size `json:"small"`
	Thumb  Size `json:"thumb"`
	Large  Size `json:"large"`
}

type Size struct {
	W      int    `json:"w"`
	H      int    `json:"h"`
	Resize string `json:"resize"`
}

type SearchMetadata struct {
	CompletedIn float64 `json:"completed_in"`
	MaxID       uint64  `json:"max_id"`
	MaxIDStr    string  `json:"max_id_str"`
	NextResults string  `json:"next_results"`
	Query       string  `json:"query"`
	RefreshURL  string  `json:"refresh_url"`
	Count       int     `json:"count"`
	SinceID     uint64  `json:"since_id"`
	SinceIDStr  string  `json:"since_id_str"`
}

// ---- citm_catalog ----

type CitmCatalog struct {
	AreaNames                map[string]string  `json:"areaNames"`
	AudienceSubCategoryNames map[string]string  `json:"audienceSubCategoryNames"`
	BlockNames               map[string]string  `json:"blockNames"`
	Events                   map[string]Event   `json:"events"`
	Performances             []Performance      `json:"performances"`
	SeatCategoryNames        map[string]string  `json:"seatCategoryNames"`
	SubTopicNames            map[string]string  `json:"subTopicNames"`
	SubjectNames             map[string]string  `json:"subjectNames"`
	TopicNames               map[string]string  `json:"topicNames"`
	TopicSubTopics           map[string][]int64 `json:"topicSubTopics"`
	VenueNames               map[string]string  `json:"venueNames"`
}

type Event struct {
	Description *string `json:"description"`
	ID          int64   `json:"id"`
	Logo        *string `json:"logo"`
	Name        string  `json:"name"`
	SubTopicIDs []int64 `json:"subTopicIds"`
	SubjectCode *string `json:"subjectCode"`
	Subtitle    *string `json:"subtitle"`
	TopicIDs    []int64 `json:"topicIds"`
}

type Performance struct {
	EventID        int64          `json:"eventId"`
	ID             int64          `json:"id"`
	Logo           *string        `json:"logo"`
	Name           *string        `json:"name"`
	Prices         []Price        `json:"prices"`
	SeatCategories []SeatCategory `json:"seatCategories"`
	SeatMapImage   *string        `json:"seatMapImage"`
	Start          uint64         `json:"start"`
	VenueCode      string         `json:"venueCode"`
}

type Price struct {
	Amount                int64 `json:"amount"`
	AudienceSubCategoryID int64 `json:"audienceSubCategoryId"`
	SeatCategoryID        int64 `json:"seatCategoryId"`
}

type SeatCategory struct {
	Areas          []Area `json:"areas"`
	SeatCategoryID int64  `json:"seatCategoryId"`
}

type Area struct {
	AreaID   int64    `json:"areaId"`
	BlockIDs []string `json:"blockIds"`
}

// ---- canada ----

type FeatureCollection struct {
	Type     string    `json:"type"`
	Features []Feature `json:"features"`
}

type Feature struct {
	Type       string            `json:"type"`
	Properties map[string]string `json:"properties"`
	Geometry   Geometry          `json:"geometry"`
}

type Geometry struct {
	Type        string         `json:"type"`
	Coordinates [][][2]float64 `json:"coordinates"`
}

// A fresh value of the input's type
func newTyped(kind string) any {
	switch kind {
	case "twitter":
		return new(Twitter)
	case "citm_catalog":
		return new(CitmCatalog)
	default:
		return new(FeatureCollection)
	}
}

// The typed check line (see ../reference.py)
func typedCheck(v any) string {
	switch t := v.(type) {
	case *Twitter:
		var ids uint64
		var followers, retweets, hashtags, chars, media, descURLs int
		for i := range t.Statuses {
			s := &t.Statuses[i]
			ids += s.ID
			followers += int(s.User.FollowersCount)
			if s.RetweetedStatus != nil {
				retweets++
			}
			hashtags += len(s.Entities.Hashtags)
			chars += utf8.RuneCountInString(s.Text)
			media += len(s.Entities.Media)
			descURLs += len(s.User.Entities.Description.Urls)
		}
		return fmt.Sprintf("check: %d %d %d %d %d %d %d %d", len(t.Statuses), ids, followers, retweets, hashtags, chars, media, descURLs)
	case *CitmCatalog:
		var eventIDs, perfIDs, amounts int64
		var areas, names, subTopics int
		for _, e := range t.Events {
			eventIDs += e.ID
			names += utf8.RuneCountInString(e.Name)
		}
		for _, p := range t.Performances {
			perfIDs += p.ID
			for _, pr := range p.Prices {
				amounts += pr.Amount
			}
			for _, sc := range p.SeatCategories {
				areas += len(sc.Areas)
			}
		}
		for _, l := range t.TopicSubTopics {
			subTopics += len(l)
		}
		return fmt.Sprintf("check: %d %d %d %d %d %d %d %d", len(t.Events), eventIDs, len(t.Performances), perfIDs, amounts, areas, names, subTopics)
	case *FeatureCollection:
		var rings, points, chars int
		var sum uint64
		for _, f := range t.Features {
			rings += len(f.Geometry.Coordinates)
			for _, r := range f.Geometry.Coordinates {
				points += len(r)
				for _, p := range r {
					sum += numBits(p[0]) + numBits(p[1])
				}
			}
			for _, v := range f.Properties {
				chars += utf8.RuneCountInString(v)
			}
		}
		return fmt.Sprintf("check: %d %d %d %016x %d", len(t.Features), rings, points, sum, chars)
	}
	return "check: ?"
}

// ---- json-partial (query track): only the queried fields ----

type partialTwitter struct {
	Statuses []struct {
		User struct {
			FollowersCount int64 `json:"followers_count"`
		} `json:"user"`
		Entities struct {
			Hashtags []struct{} `json:"hashtags"`
		} `json:"entities"`
	} `json:"statuses"`
}

type partialCitm struct {
	Performances []struct {
		ID int64 `json:"id"`
	} `json:"performances"`
}

type partialCanada struct {
	Features []struct {
		Geometry struct {
			Coordinates [][][]float64 `json:"coordinates"`
		} `json:"geometry"`
	} `json:"features"`
}
