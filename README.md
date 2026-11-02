# Noir & Gold shop: setup guide

You have three files:

| File | What it is |
|---|---|
| `index.html` | The whole shop. This is the file you put on GitHub Pages. |
| `supabase-setup.sql` | Creates the database, security rules and photo storage. You run it once. |
| `README.md` | This guide. |

Everything below is free and needs no credit card. Set aside about 20 minutes.

---

## Step 1. Create the Supabase project

1. Go to https://supabase.com and sign up (GitHub login is fine).
2. Click **New project**. Pick any name, choose a database password (save it somewhere), and choose the region closest to the Philippines (Southeast Asia, Singapore).
3. Wait about two minutes until the project finishes setting up.

## Step 2. Turn off email confirmation

This lets customers log in right after they sign up, without waiting for an email.

1. In your project, open **Authentication**, then **Sign In / Providers** (older dashboards: **Providers**).
2. Open **Email**.
3. Turn **Confirm email** off, then **Save**.

If you leave it on, the shop still works, but each new customer must click a confirmation link first. Supabase's free email sending is limited to a few emails per hour, so turning it off is easier.

## Step 3. Create the owner account

1. Open **Authentication**, then **Users**.
2. Click **Add user**, then **Create new user**.
3. Enter the owner's email and a password. Tick **Auto Confirm User** if you see it.
4. Click **Create user**.

This email and password are what you will use for **Admin login** on the shop.

## Step 4. Run the database script

1. Open `supabase-setup.sql` in any text editor.
2. Near the bottom, find this line and put in the same email you used in Step 3:

   ```
   owner_email text := 'owner@example.com';   -- >>> CHANGE THIS <<<
   ```

3. In Supabase, open **SQL Editor**, then **New query**.
4. Paste the whole file and click **Run**.
5. At the bottom it should say **Success**. In the messages area you should also see `Owner set: your@email.com`.

If it says `No change`, the email does not match an account from Step 3. Fix the email and run the script again. It is safe to run more than once.

## Step 5. Connect the shop to your project

1. In Supabase, open **Project Settings**, then **API** (older dashboards: **Settings, API**).
2. Copy the **Project URL** (looks like `https://abcdxyz.supabase.co`).
3. Copy the **anon public** key (a long string starting with `eyJ`).
4. Open `index.html` in a text editor. Near the top, find:

   ```js
   window.SHOP_CONFIG = {
     SUPABASE_URL: "PASTE_YOUR_PROJECT_URL_HERE",
     SUPABASE_ANON_KEY: "PASTE_YOUR_ANON_PUBLIC_KEY_HERE"
   };
   ```

5. Paste your two values between the quotes and save.

The anon key is safe to publish. It is not a secret. The security rules from Step 4 are what protect your data. Never put the **service_role** key anywhere in this file.

## Step 6. Put it on GitHub Pages

1. On GitHub, create a new repository (public is fine).
2. Upload `index.html` to the repository's main folder. Keep the name exactly `index.html`.
3. Open the repository's **Settings**, then **Pages**.
4. Under **Build and deployment**, set **Source** to **Deploy from a branch**, choose the `main` branch and the `/ (root)` folder, then **Save**.
5. After a minute or two, your shop is live at `https://YOUR-USERNAME.github.io/YOUR-REPO/`.

## Step 7. Tell Supabase your shop's address

This makes password-reset emails link back to your shop.

1. In Supabase, open **Authentication**, then **URL Configuration**.
2. Set **Site URL** to your GitHub Pages address from Step 6.
3. Under **Redirect URLs**, add the same address, then save.

---

## First things to do in your shop

1. Open your shop and click **Owner login** in the footer (or **Log in**, then **Admin login**). Sign in with the owner email and password.
2. Go to **Dashboard, Settings**:
   - Set your shop name, tagline, contact and payment instructions.
   - Upload your payment QR code (from GCash, Maya or your bank).
   - Change the owner password if you want a different one.
3. Go to **Dashboard, Products** and add your bags and wallets with photos, prices and stock.
4. Place a test order from a second browser (or a private window) to see the buyer side.

## How ordering works

- Customers create an account (name, mobile, address, email, password) and log in.
- At checkout they choose QR code, cash on delivery, or cash on pick up.
- QR customers see your QR code with the exact amount, can download it, and tap **I've paid**. You see "Customer reported payment" on the order. Check your GCash or Maya yourself before you accept.
- You accept or decline each order in **Dashboard, Orders**. Accepting takes the items out of stock. If an item has run out, the order cannot be accepted.
- The dashboard refreshes by itself every 20 seconds, and the **Refresh** button on the Orders tab updates it right away.

## Good to know

- **Free plan pause.** Supabase pauses free projects after about a week with no activity. If your shop ever shows "The shop is not loading", open your project in the Supabase dashboard and click **Restore project**. Regular visits keep it awake.
- **Forgot the owner password.** On the owner login, use the customer **Log in, Forgot password?** link with the owner email, or reset the user in **Authentication, Users** in Supabase.
- **Adding a second owner.** Create the user in Step 3's screen, then in the SQL Editor run: `insert into public.admins (user_id) select id from auth.users where email = 'second@example.com';`
- **Changing the look.** Colors are the variables at the top of the `<style>` block in `index.html` (`--gold`, `--ink` and so on).
- **Backups.** Supabase keeps your data, but export your orders now and then from **Table Editor, orders**.
