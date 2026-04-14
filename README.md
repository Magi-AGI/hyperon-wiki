# CHANGES TO DECKO

## DONE
- TinyMCE fullscreen button enabled

## IN PROGRESS
- Decko modal made full screen

## PLANNED

# DECKO 
The site is a wiki meant to utilize Decko's unique "everything is a card" flexibility to support a hypergraph of cards about the SNET Hyperon ecosystem and Atomspace cognitive architectures.

## Design Methodology
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
- Renamed "Getting started" menu to Start
- Renamed "Recent Changes" to a Recent
- Rename username on every page to Account
    - Show user avatar once it is supported
- Rename "Sign up" to "Register"
- Rename "Sign in" to "Login"
- Rename "Sign out" to "Logout"
- Search box should be a collapsible small search square with just a search icon by default until you click it to expand to the search box or a search string has been entered.
- Add Light/dark theme toggle button

### Always visible Navigation
Navigation UI needs to be visible when you scroll.
- The top *navbox needs to stay visible on the top of the page when you scroll  
- A 
- The left sidebar with the accordion Page Hiererchy Menu needs to stay visible when you scroll
- The right sidebar with Page Contents needs to stay visible when you scroll

#### Page Section Boxes
Page Section Boxes need to be highly navigable and the current section needs to stay visible on the top as you scroll from section to section so you know which section you are in if you are in a long section.
- The page contents feature expandable/collapsible section boxes which are listed in the Right Sidebar's Page Contents Box.

### +*account_settings
account_settings pages need to support user avatar pictures.
- Check for available Decko mods that implement this.

## LEFT SIDEBAR LAYOUT
The Decko currently uses the "Left sidebar layout" under *layout.

### Left Sidebar

#### Page Hierarchy Menu Mod
A mod is needed to generate a conventional expandable collapsible accordion menu hierarchy for a large wiki of pages like the one on the Obsidian Docs pages (See Inspirations).
- The left sidebar needs to use a Page Hierarchy Menu Mod to be able to accordion by default to collapse all top level pages except that it expands only the top level page parent of the pages you are currently in.
- The files that implement this:
    - wiki_nav_tree.rb
    - wiki_nav_tree.scss
    - wiki_nav_tree_spec.rb
### Right Sidebar
The right sidebar should show a Local Graph box and a Page Contents link hierarchy.

#### Local Graph Box
- The top right should show a local graph showing how the current page connects to linked and hierarchically connected pages.

#### Page Contents Menu
-The right sidebar should show a "Page Contents" table of contents of the section headers for the current page.

## Ben's Feedback
Ben had some initial feedback on the stock Decko themed site:
    "The basic organization of https://wiki.hyperon.dev/ looks fine to me, I mean the idea of a wiki is to be stripped down not fancy and it's all about the content...

    I wonder if there is a way to select the topic of interest and click to make it the TOP of the page for a while, so one is not  trapped by the right margin of the page.   I.e. if one's main interest at the. moment is some topic T that is at the third level of indenting and its subtopics, then it would be good to be able to put T at the top (by the left margin) for a while rather than having the feeling one is deep in a subsubsubmenu all the time...  HOWEVER this is a nice-to-have and not a blocker for being able to launch something...

    In general I am extremely eager to move this website and wiki to launch, and wondering if somehow we could/should have done all this more simply so we would have something on the web a while ago instead of still iterating, iterating, iterating, iterating... !"