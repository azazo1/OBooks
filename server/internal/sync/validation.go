package sync

import (
	"encoding/json"
	"net/url"
	"path"
	"strings"
)

func safePath(value string, allowEmpty bool) bool {
	if value == "" { return allowEmpty }
	value = strings.SplitN(value, "#", 2)[0]
	decoded, err := url.PathUnescape(value)
	if err != nil { return false }
	return decoded != "" && !strings.HasPrefix(decoded, "/") && decoded != ".." && !strings.HasPrefix(decoded, "../") &&
		!strings.Contains(decoded, "\\") && !strings.ContainsRune(decoded, 0) && path.Clean(decoded) == decoded
}

type position struct {
	SpineID string `json:"spineID"`
	CharacterOffset int64 `json:"characterOffset"`
	ViewportOffset *float64 `json:"viewportOffset"`
}
func (p position) valid() bool { return p.SpineID != "" && len(p.SpineID) <= 4096 && p.CharacterOffset >= 0 && p.CharacterOffset <= 2147483647 }

type tocEntry struct {
	ID string `json:"id"`
	Label string `json:"label"`
	Href string `json:"href"`
	Children []tocEntry `json:"children"`
}

func validTOC(entries []tocEntry, depth int) bool {
	if depth > 50 { return false }
	for _, entry := range entries {
		if !uuidPattern.MatchString(entry.ID) || !safePath(entry.Href, true) || entry.Children == nil || !validTOC(entry.Children, depth+1) { return false }
	}
	return true
}

func validPayload(entity string, data json.RawMessage) bool {
	var object map[string]json.RawMessage
	if json.Unmarshal(data, &object) != nil || object == nil { return false }
	var required []string
	switch entity {
	case "book": required = []string{"title", "authors", "sortTitle", "sourceFileName", "spine", "toc", "importedAt", "isFinished", "isHiddenFromContinueReading"}
	case "progress": required = []string{"fraction"}
	case "bookmark": required = []string{"id", "position", "title", "progressFraction"}
	case "annotation": required = []string{"id", "text", "kind", "sectionIndex", "range"}
	case "readingEvent": required = []string{"id", "day", "hour", "seconds"}
	}
	for _, key := range required { if object[key] == nil || string(object[key]) == "null" { return false } }
	switch entity {
	case "book":
		var book struct {
			Title string `json:"title"`; Authors []string `json:"authors"`; SortTitle string `json:"sortTitle"`; SourceFileName string `json:"sourceFileName"`
			CoverPath *string `json:"coverPath"`; ImportedAt float64 `json:"importedAt"`; IsFinished bool `json:"isFinished"`; IsHidden bool `json:"isHiddenFromContinueReading"`
			Spine []struct { ID string `json:"id"`; Href string `json:"href"`; Title string `json:"title"`; Linear bool `json:"linear"` } `json:"spine"`
			TOC []tocEntry `json:"toc"`
		}
		if json.Unmarshal(data, &book) != nil || len(book.Title) > 10000 || book.Authors == nil || book.Spine == nil || book.TOC == nil || len(book.Spine) > 50000 { return false }
		if book.CoverPath != nil && !safePath(*book.CoverPath, false) { return false }
		for _, chapter := range book.Spine { if !safePath(chapter.Href, false) { return false } }
		return validTOC(book.TOC, 0)
	case "progress":
		var p struct { Fraction float64 `json:"fraction"`; Position *position `json:"position"`; LastOpenedAt *float64 `json:"lastOpenedAt"` }
		return json.Unmarshal(data, &p) == nil && p.Fraction >= 0 && p.Fraction <= 1 && (p.Position == nil || p.Position.valid())
	case "bookmark":
		var b struct { ID string `json:"id"`; Position position `json:"position"`; Title string `json:"title"`; ProgressFraction float64 `json:"progressFraction"`; ModifiedAt *float64 `json:"modifiedAt"` }
		return json.Unmarshal(data, &b) == nil && b.Position.valid() && b.ProgressFraction >= 0 && b.ProgressFraction <= 1
	case "annotation":
		var a struct { ID string `json:"id"`; Text string `json:"text"`; Quote *string `json:"quote"`; Kind string `json:"kind"`; SectionIndex int `json:"sectionIndex"`; Range []int64 `json:"range"`; ModifiedAt *float64 `json:"modifiedAt"`; ConflictOf *string `json:"conflictOf"` }
		return json.Unmarshal(data, &a) == nil && (a.Kind == "note" || a.Kind == "highlight") && a.SectionIndex >= 0 && a.SectionIndex < 50000 &&
			len(a.Range) == 2 && a.Range[0] >= 0 && a.Range[1] > 0 && a.Range[0] <= 2147483647-a.Range[1] && len(a.Text) <= 1<<20
	case "readingEvent":
		var e struct { ID string `json:"id"`; Seconds float64 `json:"seconds"`; Hour int `json:"hour"`; Day struct { Year, Month, Day int } `json:"day"` }
		return json.Unmarshal(data, &e) == nil && e.Seconds > 0 && e.Hour >= 0 && e.Hour < 24 && e.Day.Year >= 1970 && e.Day.Year <= 9999 && e.Day.Month >= 1 && e.Day.Month <= 12 && e.Day.Day >= 1 && e.Day.Day <= 31
	}
	return false
}
