pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning

import qs.modules.common

Singleton {
    id: root
    // 10 minute
    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property string city: Config.options.bar.weather.city
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    property bool gpsActive: Config.options.bar.weather.enableGPS

    onUseUSCSChanged: {
        root.getData();
    }
    onCityChanged: {
        root.getData();
    }

    property var location: ({
            valid: false,
            lat: 0,
            long: 0
        })

    property var data: ({
            uv: 0,
            humidity: 0,
            sunrise: 0,
            sunset: 0,
            windDir: 0,
            wCode: 0,
            city: 0,
            wind: 0,
            precip: 0,
            visib: 0,
            press: 0,
            temp: 0,
            tempFeelsLike: 0,
            lastRefresh: 0
        })

    readonly property var wmoToWwo: ({
            "0": "113"  // Clear sky
            ,
            "1": "116"  // Mainly clear
            ,
            "2": "116"  // Partly cloudy
            ,
            "3": "122"  // Overcast
            ,
            "45": "248" // Fog
            ,
            "48": "248" // Depositing rime fog
            ,
            "51": "263" // Drizzle: Light
            ,
            "53": "266" // Drizzle: Moderate
            ,
            "55": "296" // Drizzle: Dense
            ,
            "56": "281" // Freezing Drizzle: Light
            ,
            "57": "284" // Freezing Drizzle: Dense
            ,
            "61": "293" // Rain: Slight
            ,
            "63": "302" // Rain: Moderate
            ,
            "65": "308" // Rain: Heavy
            ,
            "66": "311" // Freezing Rain: Light
            ,
            "67": "314" // Freezing Rain: Heavy
            ,
            "71": "323" // Snow fall: Slight
            ,
            "73": "326" // Snow fall: Moderate
            ,
            "75": "338" // Snow fall: Heavy
            ,
            "77": "350" // Snow grains
            ,
            "80": "353" // Rain showers: Slight
            ,
            "81": "356" // Rain showers: Moderate
            ,
            "82": "359" // Rain showers: Violent
            ,
            "85": "368" // Snow showers: Slight
            ,
            "86": "371" // Snow showers: Heavy
            ,
            "95": "386" // Thunderstorm: Slight or moderate
            ,
            "96": "389" // Thunderstorm with slight hail
            ,
            "99": "392"  // Thunderstorm with heavy hail
        })

    function refineData(data) {
        if (!data || data.error) {
            console.error("[WeatherService] Invalid data or location not found");
            return;
        }

        let temp = {};
        temp.uv = data?.daily?.uv_index_max?.[0] || 0;
        temp.humidity = (data?.current?.relative_humidity_2m || 0) + "%";

        let sunriseStr = data?.daily?.sunrise?.[0];
        let sunsetStr = data?.daily?.sunset?.[0];
        temp.sunrise = sunriseStr ? sunriseStr.split('T')[1] : "0.0";
        temp.sunset = sunsetStr ? sunsetStr.split('T')[1] : "0.0";

        let windDeg = data?.current?.wind_direction_10m || 0;
        const directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        let dirIndex = Math.round(windDeg / 22.5) % 16;
        temp.windDir = directions[dirIndex];

        let wmoCode = data?.current?.weather_code || 0;
        temp.wCode = root.wmoToWwo[String(wmoCode)] || "113";

        let city = "City";
        if (data?.resolved_city) {
            city = data.resolved_city;
        } else if (data?.timezone) {
            let parts = data.timezone.split('/');
            city = parts[parts.length - 1].replace('_', ' ');
        }
        temp.city = city;

        let currentTemp = Math.round(data?.current?.temperature_2m || 0);
        let feelsLike = Math.round(data?.current?.apparent_temperature || 0);

        let windSpeed = Math.round(data?.current?.wind_speed_10m || 0);
        let precipitation = data?.current?.precipitation || 0;
        let visibility = data?.current?.visibility || 0;
        let pressure = data?.current?.pressure_msl || 0;

        if (root.useUSCS) {
            temp.wind = windSpeed + " mph";
            temp.precip = precipitation + " in";
            temp.visib = (visibility / 1609.34).toFixed(0) + " m";
            temp.press = (pressure * 0.02953).toFixed(1) + " psi";
            temp.temp = currentTemp + "°F";
            temp.tempFeelsLike = feelsLike + "°F";
        } else {
            temp.wind = windSpeed + " km/h";
            temp.precip = precipitation + " mm";
            temp.visib = (visibility / 1000).toFixed(0) + " km";
            temp.press = Math.round(pressure) + " hPa";
            temp.temp = currentTemp + "°C";
            temp.tempFeelsLike = feelsLike + "°C";
        }

        temp.lastRefresh = DateTime.time + " • " + DateTime.date;
        root.data = temp;
    }

    function getData() {
        let tempUnit = root.useUSCS ? "fahrenheit" : "celsius";
        let windUnit = root.useUSCS ? "mph" : "kmh";
        let precipUnit = root.useUSCS ? "inch" : "mm";

        let command = "";
        if (root.gpsActive && root.location.valid) {
            command = `
LAT="${root.location.lat}"
LON="${root.location.long}"
NAME=""
`;
        } else {
            let escapedCity = encodeURIComponent(root.city.trim());
            command = `
GEO=$(curl -s "https://geocoding-api.open-meteo.com/v1/search?name=${escapedCity}&count=1&language=en&format=json")
LAT=$(echo "$GEO" | jq -r '.results[0].latitude // empty')
LON=$(echo "$GEO" | jq -r '.results[0].longitude // empty')
NAME=$(echo "$GEO" | jq -r '.results[0].name // empty')
`;
        }

        command += `
if [ -n "$LAT" ]; then
    RES=$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,visibility&daily=sunrise,sunset,uv_index_max&timezone=auto&temperature_unit=${tempUnit}&wind_speed_unit=${windUnit}&precipitation_unit=${precipUnit}")
    if [ -n "$NAME" ]; then
        echo "$RES" | jq --arg name "$NAME" '. + {resolved_city: $name}'
    else
        echo "$RES"
    fi
else
    echo '{"error": "Location not found"}'
fi
`;

        fetcher.command[2] = command;
        fetcher.running = true;
    }

    Component.onCompleted: {
        if (!root.gpsActive)
            return;
        console.info("[WeatherService] Starting the GPS service.");
        positionSource.start();
    }

    Process {
        id: fetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0)
                    return;
                try {
                    const parsedData = JSON.parse(text);
                    root.refineData(parsedData);
                    // console.info(`[ data: ${JSON.stringify(parsedData)}`);
                } catch (e) {
                    console.error(`[WeatherService] ${e.message}`);
                }
            }
        }
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval

        onPositionChanged: {
            // update the location if the given location is valid
            // if it fails getting the location, use the last valid location
            if (position.latitudeValid && position.longitudeValid) {
                root.location.lat = position.coordinate.latitude;
                root.location.long = position.coordinate.longitude;
                root.location.valid = true;
                // console.info(`📍 Location: ${position.coordinate.latitude}, ${position.coordinate.longitude}`);
                root.getData();
                // if can't get initialized with valid location deactivate the GPS
            } else {
                root.gpsActive = root.location.valid ? true : false;
                console.error("[WeatherService] Failed to get the GPS location.");
            }
        }

        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop();
                root.location.valid = false;
                root.gpsActive = false;
                Quickshell.execDetached(["notify-send", Translation.tr("Weather Service"), Translation.tr("Cannot find a GPS service. Using the fallback method instead."), "-a", "Shell"]);
                console.error("[WeatherService] Could not aquire a valid backend plugin.");
            }
        }
    }

    Timer {
        running: !root.gpsActive
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: !root.gpsActive
        onTriggered: root.getData()
    }
}
