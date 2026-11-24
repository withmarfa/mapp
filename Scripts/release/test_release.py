"""Tests for version.py, appcast.py and release_notes.py. Run: python3 -m unittest discover -s Scripts/release"""

import datetime
import io
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import appcast
import release_notes
import version

HERE = Path(__file__).parent
FIXTURES = HERE / "fixtures"
DOWNLOADS = "https://downloads.example.com/marfa-mac/"
RELEASES = "https://github.com/withmarfa/marfa-mac/releases"
NS = {"sparkle": appcast.SPARKLE}
PUBLISHED = datetime.datetime(2026, 11, 23, 12, 0, tzinfo=datetime.timezone.utc)


def add(feed, tag, notes="", signature="SIG==", length=123):
    release = version.parse(tag)
    name = f"Marfa-{tag.removeprefix('v')}.dmg"
    return appcast.build(feed, release, DOWNLOADS, name, signature, length, notes, RELEASES, PUBLISHED)


def items(tree):
    return tree.getroot().find("channel").findall("item")


def builds(tree):
    return [appcast.item_build(item) for item in items(tree)]


def reparse(tree):
    """The feed as a reader gets it: written out and read back."""
    path = Path(tempfile.mkdtemp()) / "appcast.xml"
    tree.write(path, encoding="utf-8", xml_declaration=True)
    return ET.parse(path), path.read_text(encoding="utf-8")


class VersionTests(unittest.TestCase):
    def test_a_release_and_a_candidate_are_numbered_as_decided(self):
        self.assertEqual(version.parse("v0.0.59-rc1").build, 5901)
        self.assertEqual(version.parse("v0.0.59").build, 5999)
        self.assertEqual(version.parse("v1.2.3").build, 10_000_000 + 200_000 + 300 + 99)
        self.assertEqual(version.parse("v0.0.59-rc98").build, 5998)

    def test_a_candidate_sorts_below_its_release_and_above_the_release_before(self):
        self.assertLess(version.parse("v0.0.58").build, version.parse("v0.0.59-rc1").build)
        self.assertLess(version.parse("v0.0.59-rc2").build, version.parse("v0.0.59").build)
        self.assertLess(version.parse("v0.0.59").build, version.parse("v0.0.60-rc1").build)

    def test_the_version_drops_the_candidate_suffix(self):
        release = version.parse("v0.0.59-rc3")
        self.assertEqual((release.version, release.candidate, release.channel), ("0.0.59", True, "beta"))
        release = version.parse("v0.0.59")
        self.assertEqual((release.version, release.candidate, release.channel), ("0.0.59", False, "default"))

    def test_a_tag_that_is_not_a_version_is_refused(self):
        for tag in [
            "", "0.0.59", "v0.0", "v1", "v0.0.59.1", "v0.0.59-rc", "v0.0.59-rc0", "v0.0.59-rc01", "v0.0.59-beta1",
            "v0.0.059", "v0.0.59-rc1-x", "v0.0.59 ", " v0.0.59", "v0.0.59\n", "V0.0.59", "vx.y.z", "v0.0.-1",
        ]:
            with self.subTest(tag=tag), self.assertRaises(version.TagError):
                version.parse(tag)

    def test_version_zero_is_refused(self):
        for tag in ["v0.0.0", "v0.0.0-rc1"]:
            with self.subTest(tag=tag), self.assertRaisesRegex(version.TagError, "0.0.0"):
                version.parse(tag)

    def test_a_number_that_would_overflow_its_place_is_refused(self):
        for tag in ["v100.0.0", "v0.100.0", "v0.0.1000", "v0.0.1-rc99"]:
            with self.subTest(tag=tag), self.assertRaises(version.TagError):
                version.parse(tag)

    def test_the_command_prints_outputs_and_fails_on_a_bad_tag(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(version.main(["version.py", "v0.0.59-rc1"]), 0)
        self.assertEqual(
            out.getvalue().splitlines(),
            ["tag=v0.0.59-rc1", "version=0.0.59", "build=5901", "candidate=true", "channel=beta"],
        )
        with redirect_stderr(io.StringIO()) as err:
            self.assertEqual(version.main(["version.py", "v0.0"]), 1)
        self.assertIn("::error::", err.getvalue())


class AppcastTests(unittest.TestCase):
    def test_a_new_feed_holds_the_release(self):
        tree = add(None, "v0.0.59", notes=(FIXTURES / "notes-generated.md").read_text())
        self.assertEqual(builds(tree), [5999])
        item = items(tree)[0]
        self.assertEqual(item.findtext("title"), "Marfa 0.0.59")
        self.assertEqual(item.findtext("pubDate"), "Mon, 23 Nov 2026 12:00:00 GMT")
        self.assertEqual(item.findtext("sparkle:shortVersionString", namespaces=NS), "0.0.59")
        self.assertEqual(item.findtext("sparkle:minimumSystemVersion", namespaces=NS), "27.0.0")
        self.assertEqual(item.findtext("sparkle:fullReleaseNotesLink", namespaces=NS), RELEASES)
        self.assertIsNone(item.find("sparkle:channel", NS))
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), DOWNLOADS + "Marfa-0.0.59.dmg")
        self.assertEqual(enclosure.get("length"), "123")
        self.assertEqual(enclosure.get("type"), "application/octet-stream")
        self.assertEqual(enclosure.get(appcast.sparkle("edSignature")), "SIG==")

    def test_the_written_feed_uses_the_sparkle_prefix_and_reads_back(self):
        tree, text = reparse(add(None, "v0.0.59"))
        self.assertIn("<sparkle:version>5999</sparkle:version>", text)
        self.assertIn('sparkle:edSignature="SIG=="', text)
        self.assertEqual(builds(tree), [5999])

    def test_a_release_goes_in_front_of_an_existing_feed_and_keeps_its_items(self):
        feed = ET.parse(FIXTURES / "feed-existing.xml")
        tree = add(feed, "v0.0.59")
        self.assertEqual(builds(tree), [5999, 5899, 5801])
        old = items(tree)[1].find("enclosure")
        self.assertEqual(old.get(appcast.sparkle("edSignature")), "OLD58==")
        self.assertEqual(items(tree)[1].findtext("description"), "<p>Older notes.</p>")

    def test_a_candidate_is_in_the_beta_channel_and_a_release_is_in_none(self):
        feed = ET.parse(FIXTURES / "feed-existing.xml")
        tree = add(feed, "v0.0.59-rc1")
        newest = items(tree)[0]
        self.assertEqual(appcast.item_build(newest), 5901)
        self.assertEqual(newest.findtext("sparkle:channel", namespaces=NS), "beta")
        self.assertEqual([appcast.item_channel(item) for item in items(tree)], ["beta", "", "beta"])
        self.assertEqual(newest.find("enclosure").get("url"), DOWNLOADS + "Marfa-0.0.59-rc1.dmg")
        self.assertEqual(newest.findtext("sparkle:shortVersionString", namespaces=NS), "0.0.59")

    def test_a_rebuilt_tag_replaces_its_item(self):
        first = add(ET.parse(FIXTURES / "feed-existing.xml"), "v0.0.59", signature="FIRST==", length=1)
        again, _ = reparse(first)
        tree = add(again, "v0.0.59", signature="SECOND==", length=2)
        self.assertEqual(builds(tree), [5999, 5899, 5801])
        enclosure = items(tree)[0].find("enclosure")
        self.assertEqual(enclosure.get(appcast.sparkle("edSignature")), "SECOND==")
        self.assertEqual(enclosure.get("length"), "2")

    def test_a_rebuilt_old_tag_keeps_the_feed_in_order(self):
        feed = add(ET.parse(FIXTURES / "feed-existing.xml"), "v0.0.59")
        tree = add(feed, "v0.0.58", signature="REBUILT==")
        self.assertEqual(builds(tree), [5999, 5899, 5801])
        self.assertEqual(items(tree)[1].find("enclosure").get(appcast.sparkle("edSignature")), "REBUILT==")

    def test_each_channel_keeps_its_newest_ten(self):
        tree = None
        for patch in range(1, 13):
            tree = add(tree, f"v0.0.{patch}")
            tree = add(tree, f"v0.0.{patch}-rc1")
        releases = [appcast.item_build(item) for item in items(tree) if appcast.item_channel(item) == ""]
        candidates = [appcast.item_build(item) for item in items(tree) if appcast.item_channel(item) == "beta"]
        self.assertEqual(releases, [patch * 100 + 99 for patch in range(12, 2, -1)])
        self.assertEqual(candidates, [patch * 100 + 1 for patch in range(12, 2, -1)])
        self.assertEqual(len(items(tree)), 20)

    def test_a_flood_of_candidates_never_pushes_a_release_out(self):
        tree = add(None, "v0.0.1")
        for number in range(1, 15):
            tree = add(tree, f"v0.0.2-rc{number}")
        self.assertIn(199, builds(tree))
        self.assertEqual(sum(1 for item in items(tree) if appcast.item_channel(item) == "beta"), 10)

    def test_notes_with_markup_characters_are_escaped_and_read_back_whole(self):
        notes = (FIXTURES / "notes-hostile.md").read_text()
        tree, text = reparse(add(None, "v0.0.59", notes=notes))
        self.assertNotIn("<script>", text)
        self.assertNotIn("<b>", text)
        description = items(tree)[0].findtext("description")
        self.assertNotIn("<script", description)
        self.assertIn("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; friends", description)
        self.assertIn("a &lt; b &amp;&amp; c &gt; d", description)
        self.assertIn("&quot;quotes&quot;", description)
        self.assertIn("]]&gt; not a CDATA end &amp; &lt;b&gt;not bold&lt;/b&gt;", description)
        self.assertIn('<a href="https://example.com/?a=1&amp;b=2">https://example.com/?a=1&amp;b=2</a>', description)
        # What a reader sees in the item's HTML is only the tags this script writes.
        tags = {part.split(">")[0].split(" ")[0] for part in description.split("<")[1:]}
        self.assertLessEqual(tags, {"h3", "/h3", "ul", "/ul", "li", "/li", "p", "/p", "a", "/a", "br"})

    def test_generated_notes_become_a_heading_a_list_and_links(self):
        notes = (FIXTURES / "notes-generated.md").read_text()
        description = appcast.notes_to_html(notes)
        self.assertNotIn("Release notes generated", description)
        self.assertTrue(description.startswith("<h3>What&#x27;s Changed</h3><ul><li>feat(settings): add Updates by @aicayzer in "))
        self.assertIn("<strong>caret</strong>", description)
        self.assertIn('<a href="https://github.com/withmarfa/marfa-mac/pull/511">', description)
        self.assertEqual(description.count("<li>"), 2)
        self.assertTrue(description.endswith("</a></p>"))
        self.assertIn("<p><strong>Full Changelog</strong>: <a ", description)

    def test_an_empty_note_gives_an_empty_description(self):
        self.assertEqual(appcast.notes_to_html(""), "")

    def test_the_command_reads_a_feed_that_does_not_exist_as_a_new_feed(self):
        folder = Path(tempfile.mkdtemp())
        notes = FIXTURES / "notes-generated.md"
        out = folder / "appcast.xml"
        args = [
            "appcast.py", "--feed", str(folder / "missing.xml"), "--out", str(out), "--tag", "v0.0.59-rc2",
            "--downloads-url", DOWNLOADS, "--signature", "SIG==", "--length", "42", "--notes", str(notes),
            "--releases-url", RELEASES, "--date", "2026-11-23T12:00:00+00:00",
        ]
        self.assertEqual(appcast.main(args), 0)
        tree = ET.parse(out)
        self.assertEqual(builds(tree), [5902])
        self.assertEqual(items(tree)[0].find("enclosure").get("url"), DOWNLOADS + "Marfa-0.0.59-rc2.dmg")

    def test_the_command_refuses_a_bad_tag_and_a_feed_that_is_not_xml(self):
        folder = Path(tempfile.mkdtemp())
        common = [
            "--out", str(folder / "out.xml"), "--downloads-url", DOWNLOADS, "--signature", "S", "--length", "1",
            "--releases-url", RELEASES,
        ]
        with redirect_stderr(io.StringIO()):
            self.assertEqual(appcast.main(["appcast.py", "--tag", "v0.0", *common]), 1)
            broken = folder / "broken.xml"
            broken.write_text("<rss><channel>")
            self.assertEqual(appcast.main(["appcast.py", "--tag", "v0.0.59", "--feed", str(broken), *common]), 1)
        self.assertFalse((folder / "out.xml").exists())


if __name__ == "__main__":
    sys.exit(unittest.main())


class ReleaseNotesTests(unittest.TestCase):
    def test_lists_what_a_person_notices_by_section_and_leaves_out_the_rest(self):
        subjects = [
            "ci: run the release build on main and skip unneeded UI-test builds (#535)",
            "fix(sign-in): ask for every app's data scope, which a first sign-in needs (#531)",
            "feat(settings): choose which app opens Marfa links (#534)",
            "fix(release): measure a file's size with wc, which works on linux (#528)",
            "chore(deps): move marfa-swift to v0.0.90 (#512)",
            "perf(views): a keystroke redraws only the page (#518)",
            "test: drop the busy-mac memory bound and wall clock (#488) (#515)",
            "docs(app): name Sparkle among what connects out",
            "fix(model)!: accept only a server address with no path (#524)",
        ]
        self.assertEqual(
            release_notes.notes(subjects),
            "### New\n- Choose which app opens Marfa links\n\n"
            "### Fixed\n- Ask for every app's data scope, which a first sign-in needs\n"
            "- Accept only a server address with no path\n\n"
            "### Faster\n- A keystroke redraws only the page\n",
        )

    def test_leaves_out_the_pull_request_numbers(self):
        text = release_notes.notes(["fix(editor): keep the caret in place (#512)", "fix: undo a merge (#488) (#515)"])
        self.assertEqual(text, "### Fixed\n- Keep the caret in place\n- Undo a merge\n")

    def test_says_so_when_nothing_a_person_notices_changed(self):
        self.assertEqual(release_notes.notes(["ci: lint", "chore: tidy", "Merge branch 'main'"]), release_notes.NOTHING + "\n")

    def test_a_repeated_subject_is_listed_once(self):
        text = release_notes.notes(["fix(app): one thing (#1)", "fix(app): one thing (#2)"])
        self.assertEqual(text.count("One thing"), 1)

    def test_the_notes_read_as_html_in_the_appcast(self):
        html_text = appcast.notes_to_html(release_notes.notes(["feat(app): add <b> & \"quotes\" (#9)"]))
        self.assertEqual(html_text, "<h3>New</h3><ul><li>Add &lt;b&gt; &amp; &quot;quotes&quot;</li></ul>")
