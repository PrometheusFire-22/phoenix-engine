# ============================================================================
# Project Chronos: Main Frontend Application
# ============================================================================
import sys
from dash import Dash, dcc, html, Input, Output
import dash_bootstrap_components as dbc
import pandas as pd
import plotly.express as px
from sqlalchemy import text

sys.path.insert(0, "./src")
from chronos.database.connection import get_db_session

app = Dash(__name__, external_stylesheets=[dbc.themes.CYBORG])
server = app.server


def get_series_options():
    try:
        with get_db_session() as session:
            query = text(
                """
                SELECT series_id, series_name, source_series_id
                FROM metadata.series_metadata
                WHERE is_active = TRUE
                ORDER BY series_name;
            """
            )
            df = pd.read_sql_query(query, session.bind)
            options = [
                {
                    "label": f"{row['series_name']} ({row['source_series_id']})",
                    "value": row["series_id"],
                }
                for _, row in df.iterrows()
            ]
            return options
    except Exception as e:
        print(f"CRITICAL: Error fetching series options from database: {e}")
        return []


app.layout = dbc.Container(
    [
        html.H1("Project Chronos: Macroeconomic Data Viewer", className="text-light mt-4 mb-4"),
        dbc.Row(
            [
                dbc.Col(
                    dcc.Dropdown(
                        id="series-dropdown",
                        options=get_series_options(),
                        placeholder="Select a data series to visualize...",
                    ),
                    width=12,
                )
            ]
        ),
        dbc.Row(
            [
                dbc.Col(
                    dcc.Loading(
                        id="loading-chart",
                        type="default",
                        children=html.Div(id="chart-container", className="mt-4"),
                    ),
                    width=12,
                )
            ]
        ),
    ],
    fluid=True,
    className="dbc",
)


@app.callback(Output("chart-container", "children"), Input("series-dropdown", "value"))
def update_chart(selected_series_id):
    if selected_series_id is None:
        return html.P("Please select a series to view its data.", className="text-muted")

    try:
        with get_db_session() as session:
            query = text(
                """
                SELECT observation_date, value
                FROM timeseries.economic_observations
                WHERE series_id = :series_id
                ORDER BY observation_date;
            """
            )
            df = pd.read_sql_query(query, session.bind, params={"series_id": selected_series_id})

            if df.empty:
                return html.P(
                    "No observation data found for this series.", className="text-warning"
                )

            fig = px.line(
                df,
                x="observation_date",
                y="value",
                title="Historical Observations",
                template="plotly_dark",
            )
            return dcc.Graph(figure=fig)
    except Exception as e:
        print(f"ERROR: Could not generate chart for series_id {selected_series_id}: {e}")
        return html.P(f"An error occurred while generating the chart: {e}", className="text-danger")


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=8050)
