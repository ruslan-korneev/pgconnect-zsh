# PostgreSQL Connection Plugin for Oh My Zsh

This plugin enhances your Oh My Zsh setup by providing an easy way to manage and connect to PostgreSQL databases using `pgcli` and `fzf` for a seamless command-line experience.

## Requirements

Ensure you have the following tools installed before using this plugin:

-  [fzf](https://github.com/junegunn/fzf): A command-line fuzzy finder.
-  [pgcli](https://github.com/dbcli/pgcli): A Postgres client with auto-completion and syntax highlighting.

## Installation

To install the PostgreSQL Connection Plugin, follow these steps:

1. Clone the repository into your custom Oh My Zsh plugins directory:

   ```zsh
   git clone git@github.com:ruslan-korneev/pgconnect-zsh.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/pgconnect
   ```

2. Add `pgconnect` to the list of plugins in your `.zshrc` file:

   ```zsh
   plugins=(... pgconnect)
   ```

3. Reload your Zsh configuration:

   ```zsh
   source ~/.zshrc
   ```

## Usage

To manage your PostgreSQL connections, configure your `~/.pg_service.conf` file. This file allows you to define multiple database connections. Here is an example configuration:

```ini
[db1]
host=0.0.0.0
port=5862
user=username
dbname=postgres

[db2]
host=0.0.0.0
port=5432
user=postgres
dbname=mysuperdatabase
```

After setting up your `~/.pg_service.conf`, you will be able to see and select these databases from a list using the plugin.

![Example Usage](media/example.gif)

### Security Note

To keep your passwords secure, you can use the `.pgpass` file, which stores your credentials safely. If you prefer, you can also include the password directly in the `~/.pg_service.conf` file using the `password` attribute, though this is not recommended for security reasons.

For more detailed information on configuring these files, refer to the [PostgreSQL documentation on connection service files](https://www.postgresql.org/docs/current/libpq-pgservice.html) and [password file](https://www.postgresql.org/docs/current/libpq-pgpass.html).

---

Feel free to contribute to this project by submitting issues or pull requests. Enjoy seamless PostgreSQL connections with Oh My Zsh!
