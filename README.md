# CHANGES TO DECKO

## DONE
- TinyMCE fullscreen button enabled

## IN PROGRESS
- Decko modal made full screen

## PLANNED
navbar/sticky fixes → nav tree wiring → TOC → comments → dark mode → avatar → stars → local graph.

# DECKO 
The site is a wiki meant to utilize Decko's unique "everything is a card" flexibility to support a hypergraph of cards about the SNET Hyperon ecosystem and Atomspace cognitive architectures.

## Design Methodology
- **Wiki Pattern:** This is a [Wiki design pattern](https://ui-patterns.com/patterns/Wiki).
- **The Decko Way:** Wherever possible, check for existing Decko mods created by the community or ways of utilizing the unique nested rules that Decko allows for to do things "the decko way" instead of overly complex approaches that use excessive non-Decko code to achieve a less maintainable result.
- **Make Reuseable Decko Mods:** If a new kind of functionality is necessary, find a way to package it as a mod that is reuseable and shareable with the Decko community.

## Decko UI Issues
The old Decko UI has some issues.
- The boxes of content in the page contents 
- No visible nav stays on the page when you scroll, leading to no way to navigate.

## Good UI Examples
Several good wiki and docs sites can serve as role models:
- [Obsidian Docs](https://docs.obsidian.md/Home)

# UI LAYOUT
The page layout has a combination of standard Wiki and Docs navigation features.

### Top Navbox
- Logo in the top navbox should be a smaller icon with the SingularityNet symbol and the SingularityNET logo text next to it at the same height. 
    - If the page shrinks to mobile collapsible width, the logo symbol should remain but the logo text should be hidden.
- The Wiki title text that says "Hyperon Wiki" should be aligned in the center of the navbox with the collapsible menu items.
- Renamed "Getting started" menu to "Start"
- Renamed "Recent Changes" to "Recent"
- Rename username on every page to "Account" with 👤 emoji until you pick an avatar, then show the user avatar instead.
    - Show user avatar once it is supported
- Rename "Sign up" to "Register"
- Rename "Sign in" to "Login" with a 🔑 key emoji
- Rename "Sign out" to "Logout" with a ⏻ power emoji button.
- Search box should be a collapsible small search square with just a 🔎 search emoji icon by default until you click it to expand to the search box or a search string has been entered.
- Add ☀️Light/dark theme toggle button

### Always visible Navigation
Navigation UI needs to be visible when you scroll.
- The top *navbox needs to stay visible on the top of the page when you scroll  
- A 
- The left sidebar with the accordion Page Hiererchy Menu needs to stay visible when you scroll
- The right sidebar with Page Contents needs to stay visible when you scroll

#### Content Collapsible Section Boxes
Content Collapsible Section Boxes need to be highly navigable and the current section needs to stay visible on the top as you scroll from section to section so you know which section you are in if you are in a long section.
- The page contents feature expandable/collapsible section boxes which are listed in the Right Sidebar's Page Contents Box.

### +*account_settings
account_settings pages need to support user avatar pictures.
- Check for available Decko mods that implement this.

## WIKI LAYOUT
The Decko currently uses the "Left sidebar layout" under *layout. It should be switched to a new "Wiki Layout" layout based on it but with the following changed sections.

### Left Sidebar

#### Wiki Nav Tree Menu Mod
A mod is needed to generate a conventional expandable collapsible accordion menu hierarchy for a large wiki of pages like the one on the Obsidian Docs pages (See Inspirations).
- The left sidebar needs to use a Wiki Nav Tree Menu Mod to be able to accordion by default to collapse all top level pages except that it expands only the top level page parent of the pages you are currently in.
- **Button styling**: The menu options in the Navtree should have menu box styling.
    - The top level pages should have solid boxes around them.
    - The boxes at each level below that should have customizable styles (default to each level's box being 20% less opaque than the level above it)
- The files that implement this:
    - wiki_nav_tree.rb
    - wiki_nav_tree.scss
    - wiki_nav_tree_spec.rb

### Right Sidebar
The right sidebar should show 
    - a Local Graph box
    - Wiki Page Box
    - a Page Contents link hierarchy.

#### Local Graph Box
- The top right should show a local graph showing how the current page connects to linked and hierarchically connected pages.

#### Wiki Page Box
Wiki pages should have a menu of available actions that make it easier to find the Decko Card Menu options if they already exist.
- Breadcrumbs: The hierarchy of pages leading to the current page.
- 📝Edit: Edit current page.
- 🔗Links: Lists links to and from this page.
- ⭐Star: Star your favorite pages, shows a count of how many have starred it. Stored as CardName+*stars, a Pointer card whose content is a newline-separated list of user card names who starred it
- 📌Pin: This page should be at the top of navigation menus or search results rather than sorted alphabetically/chronologically. Stored globally as CardName+*pinned with an integer value for priority order if multiple pins exist.
- 💬Comments: A box where users can write comments on this page. Viewing, writing and moderating comments are separate permissions restrictable to logged in users with certain roles by adminstrators.
- Move: Move the page to a different place hierarchically (changing its + structured name in Decko).
- New: Create a new page card at the present level of hierarchy.
- New Child: Create a new page below the current one's level of hierarchy.
- Featured Image: Change the featured image for the page to show up in search results.

#### Page Contents Menu
-The right sidebar should show a "Page Contents" table of contents of the section headers for the current page.

### Page Footer
-The page footer can show comments using card-mod-comment.

# FEEDBACK
We compile feedback and itemize actionable suggestions to prioritize and complete.

## Ben's Feedback
Ben had some initial early April feedback on the stock Decko themed site:
    "The basic organization of https://wiki.hyperon.dev/ looks fine to me, I mean the idea of a wiki is to be stripped down not fancy and it's all about the content...

    I wonder if there is a way to select the topic of interest and click to make it the TOP of the page for a while, so one is not  trapped by the right margin of the page.   I.e. if one's main interest at the. moment is some topic T that is at the third level of indenting and its subtopics, then it would be good to be able to put T at the top (by the left margin) for a while rather than having the feeling one is deep in a subsubsubmenu all the time...  HOWEVER this is a nice-to-have and not a blocker for being able to launch something...

    In general I am extremely eager to move this website and wiki to launch, and wondering if somehow we could/should have done all this more simply so we would have something on the web a while ago instead of still iterating, iterating, iterating, iterating... !"