import dash
import dash_bootstrap_components as dbc
import pandas as pd
from dash import dcc, html, Input, Output
from sqlalchemy import text

# IMPORTANT: This allows the Dash app to import from the 'src' directory
import sys

sys.path.insert(0, "./src")
from chronos.database.connection import get_db_session

# Initialize the Dash app with a dark theme
app = dash.Dash(__name__, external_stylesheets=[dbc.themes.CYBORG])
server = app.server


def get_series_options():
    """Fetches series from the database to populate the dropdown."""
    try:
        with get_db_session() as session:
            query = text(
                "SELECT series_id, series_name, source_series_id FROM metadata.series_metadata ORDER BY series_name;"
            )
            df = pd.read_sql_query(query, session.bind)
            options = [
                {
                    "label": f"{row['series_name']} ({row['source_series_id']})",
                    "value": row["series_id"],
                }
                for index, row in df.iterrows()
            ]
            return options
    except Exception as e:
        print(f"Error fetching series options: {e}")
        return []


# Define the app layout
app.layout = dbc.Container(
    [
        dbc.Row(
            [dbc.Col(html.H1("Project Chronos: Data Viewer", className="text-light"), width=12)]
        ),
        dbc.Row(
            [
                dbc.Col(
                    dcc.Dropdown(
                        id="series-dropdown",
                        options=get_series_options(),
                        placeholder="Select a data series...",
                    ),
                    width=12,
                )
            ]
        ),
        dbc.Row([dbc.Col(html.Div(id="output-container", className="mt-4 text-light"), width=12)]),
    ],
    fluid=True,
    className="dbc",
)


@app.callback(Output("output-container", "children"), Input("series-dropdown", "value"))
def update_output(selected_series_id):
    if selected_series_id is None:
        return "Please select a series to view data."

    # In the next step, we will fetch and display a chart for this series_id.
    return f"You have selected Series ID: {selected_series_id}"


if __name__ == "__main__":
    # --- THIS IS THE FIX ---
    # Changed app.run_server to app.run
    app.run(debug=True, host="0.0.0.0", port=8050)
