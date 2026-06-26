# \#qbx\_weedfactory





\## Requirements

\- qbx\_core

\- ox\_lib

\- ox\_inventory

\- ox\_target

\- oxmysql

\- Renewed-Banking





Each shop location has:

\- Location name

\- Locked job name

\- Enabled/disabled toggle

\- Unlimited stations

\- Station type: grow, dry, roll, edibles, bags, bong, sell

\- Station label

\- Station box size

\- Station coords and heading

\- Station enabled/disabled toggle



Locations and stations save to the database and reload after restart.



\## In-Game Editor

Use:

```lua

/weedadmin

```



Admins can:

\- Create locations

\- Edit location names

\- Change job locks

\- Enable/disable locations

\- Add stations at their current position

\- Move stations to their current position

\- Resize stations

\- Rename stations

\- Enable/disable stations

\- Delete stations

\- Delete locations



Boss grade employees can edit only locations locked to their own job when this is enabled:

```lua

Config.AllowBossEditor = true

```



Admins are controlled by:

```lua

Config.AdminGroups = { 'admin', 'god' }

Config.AdminAce = 'benz\_weedshops.admin'

```



Example server.cfg ace:

```cfg

add\_ace group.admin benz\_weedshops.admin allow

```



\## How To Use With Any White Widow MLO

1\. Start the resource.

2\. Go inside your White Widow MLO.

3\. Run `/weedadmin`.

4\. Create a new location or open an existing one.

5\. Set the locked job, for example `whitewidow`, `smokeys`, or `cookies`.

6\. Add stations while standing at each counter, table, grow room, kitchen, or register.

7\. The station is saved instantly and refreshed for all players.



\## Helpful Coord Command

Use:

```lua

/wwcoords

```

This copies your current coords and heading to clipboard and prints them in F8.



\## Database

The script auto-creates its database tables on startup. A manual SQL file is also included:

```sql

sql/install.sql

```



\## Items

Add the items from:

```lua

sql/items.lua

```

to your ox\_inventory items.



\## Station Types

\- `grow` - grow/harvest fictional plants

\- `dry` - dry/cure flower

\- `roll` - roll joints

\- `edibles` - make edibles

\- `bags` - package 1g, 3.5g, 7g, 28g bags

\- `bong` - use bong station

\- `sell` - sell finished products



\## Expanded Products



This version includes 20 configurable strains, 7 rollable products, 8 edible products, bong effects, and 4 packaged bag weights.



Edit these in `shared/config.lua`:

\- `Config.Strains` for strain names, seeds, flower items, and base sale price.

\- `Config.Rollables` for joints/blunts, required wrap/paper item, flower amount, sale multiplier, and effect type.

\- `Config.Edibles` for brownies, cookies, gummies, chocolate, cereal bars, lollipops, and other edible recipes.

\- `Config.Weights` for packaged bag sizes.



Copy the expanded `sql/items.lua` entries into `ox\_inventory/data/items.lua` and restart `ox\_inventory`.





\## Station Target Patch

This version forces every weed location to have all default stations enabled:

\- Grow Plants

\- Dry/Cure Flower

\- Roll Joints \& Blunts

\- Make Edibles

\- Package Weed Bags

\- Pack Bong

\- Sell Products



All stations are registered through ox\_target box zones. Existing database locations are automatically backfilled with missing stations on resource start. New locations created through `/weedadmin` automatically spawn every station enabled by default near the creator's position.



\## Renewed-Banking Business Accounts



This build is cleaned for native Qbox + Renewed-Banking society/business funds only.



In `shared/config.lua`:



```lua

Config.CustomerRequireBusinessDeposit = true

Config.CustomerBusinessDeposit = {

&#x20;   mode = 'renewed-banking',

&#x20;   accountPrefix = '',

&#x20;   reason = 'weedfactory-customer-sale',

}

```



Use `accountPrefix = ''` when your Renewed-Banking account is the job name, for example `whitewidow`.

Use `accountPrefix = 'society\_'` only if your Renewed-Banking account is named like `society\_whitewidow`.



Make sure `Renewed-Banking` starts before `qbx\_weedfactory` in `server.cfg`.



Customer purchases, boss deposits, boss withdrawals, and balance checks all use Renewed-Banking. Legacy society-banking fallbacks were removed from the code.



\## Multi-Craft Update



All crafting/processing menus now support multi-craft amounts through `Config.MultiCraft` in `shared/config.lua`.



Supported everywhere:

\- Grow plants

\- Dry/cure flower

\- Roll joints/blunts

\- Make edibles

\- Pack/use bong station

\- Package bags by weight



Default menu amounts are x1, x5, x10, x25, x50, and Craft Max. The server re-checks all ingredients before completing the craft, multiplies ingredient removal/rewards by the selected amount, and caps one craft action with `Config.MultiCraft.MaxPerCraft`.





\## Organized crafting menu categories



Crafting menus are now split into category pages before the final recipe/strain selection:



\- Grow / Dry / Bong menus: Indica, Sativa, Hybrid, Premium, Signature strains

\- Roll menu: Joints, Premium Joints, Blunts, Signature Rolls

\- Edibles menu: Baked Goods, Candy, Bars \& Treats, Drinks

\- Bag menu: Small Bags, Large Bags, Bulk Bags



You can customize labels, icons, order, and strain placement in `shared/config.lua`:



\- `Config.MenuCategoryOrder`

\- `Config.MenuCategories`

\- `Config.StrainCategories`



You can also add `category = 'category\_key'` directly inside any rollable, edible, bag, or strain config entry to force it into a specific menu category.



\## Customer Store Menu Cleanup



The public customer dispensary menu is now split into cleaner shopping categories:



\- Flower Bags

\- Pre-Rolls / Joints

\- Blunts

\- Edibles

\- Accessories



Each category opens into product-type subcategories, then strain/product choices. Customer purchases now use a cleaner add-to-cart flow with quick-buy amounts, custom quantity, cart line totals, and a clearer cash/bank checkout screen.



Config options added in `shared/config.lua`:



```lua

Config.CustomerMenuOrder = { 'bags', 'joints', 'blunts', 'edibles', 'bongs' }

Config.CustomerQuickBuyAmounts = { 1, 2, 5, 10 }

```



