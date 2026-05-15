from mcp.server.fastmcp import FastMCP

# Initialize MCP server
mcp = FastMCP("weather-demo")

@mcp.tool()
def get_weather(city: str) -> str:
    """Get current weather for a city."""
    # Hardcoded for demo - real version would call weather API
    weather_data = {
        "Chennai": "32°C, humid, partly cloudy",
        "San Francisco": "18°C, foggy",
        "New York": "22°C, sunny",
        "London": "15°C, rainy"
    }
    return weather_data.get(city, f"Weather data not available for {city}")

@mcp.tool()
def get_forecast(city: str, days: int = 3) -> dict:
    """Get N-day forecast for a city."""
    # Mock forecast data
    forecasts = ["sunny", "partly cloudy", "rainy", "cloudy", "stormy"]
    return {
        "city": city,
        "days": days,
        "forecast": forecasts[:days]
    }

if __name__ == "__main__":
    # Run server with stdio transport (default)
    mcp.run()
