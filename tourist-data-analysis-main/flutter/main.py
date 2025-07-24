from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from typing import Optional, List
import uvicorn
from datetime import datetime
import os
import uuid
import shutil
import json
from pathlib import Path

app = FastAPI(title="Location API", version="1.0.0")

# Create directories for uploaded images and location logs
UPLOAD_DIR = "uploaded_images"
LOCATION_LOG_DIR = "location_logs"
Path(UPLOAD_DIR).mkdir(exist_ok=True)
Path(LOCATION_LOG_DIR).mkdir(exist_ok=True)

# Static file serving configuration
app.mount("/images", StaticFiles(directory=UPLOAD_DIR), name="images")

# Store recent location data in memory (reset on server restart)
recent_locations = []
image_locations = []

class LocationData(BaseModel):
    latitude: float
    longitude: float
    accuracy: Optional[float] = None
    timestamp: Optional[str] = None

class LocationResponse(BaseModel):
    status: str
    message: str
    received_data: Optional[LocationData] = None

class ImageUploadResponse(BaseModel):
    status: str
    message: str
    filename: str
    image_url: str
    location: Optional[dict] = None

class LocationLogEntry(BaseModel):
    id: str
    latitude: float
    longitude: float
    accuracy: Optional[float]
    timestamp: str
    received_at: str
    source: str  # "location_api" or "image_upload"

def save_location_to_file(location_data: dict, source: str):
    """Save location information to file"""
    log_entry = {
        "id": str(uuid.uuid4()),
        "latitude": location_data["latitude"],
        "longitude": location_data["longitude"],
        "accuracy": location_data.get("accuracy"),
        "timestamp": location_data.get("timestamp"),
        "received_at": datetime.now().isoformat(),
        "source": source
    }
    
    # Save to daily log file
    today = datetime.now().strftime("%Y-%m-%d")
    log_file = os.path.join(LOCATION_LOG_DIR, f"locations_{today}.json")
    
    # Read existing logs
    logs = []
    if os.path.exists(log_file):
        try:
            with open(log_file, 'r', encoding='utf-8') as f:
                logs = json.load(f)
        except:
            logs = []
    
    # Add new log
    logs.append(log_entry)
    
    # Save to file
    with open(log_file, 'w', encoding='utf-8') as f:
        json.dump(logs, f, ensure_ascii=False, indent=2)
    
    return log_entry

@app.get("/locations", response_class=HTMLResponse)
async def show_locations():
    """Location information web page"""
    html_content = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Location Information Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        
        .header h1 {
            color: #333;
            font-size: 2.5rem;
            margin-bottom: 10px;
        }
        
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: linear-gradient(45deg, #667eea, #764ba2);
            color: white;
            padding: 20px;
            border-radius: 15px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
        }
        
        .stat-number {
            font-size: 2rem;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .stat-label {
            font-size: 0.9rem;
            opacity: 0.9;
        }
        
        .controls {
            display: flex;
            gap: 15px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .btn {
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 20px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .btn:hover {
            background: #0056b3;
            transform: translateY(-1px);
        }
        
        .btn-danger {
            background: #dc3545;
        }
        
        .btn-danger:hover {
            background: #c82333;
        }
        
        .location-list {
            background: white;
            border-radius: 15px;
            padding: 20px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.05);
        }
        
        .location-item {
            border: 1px solid #e9ecef;
            border-radius: 10px;
            padding: 15px;
            margin-bottom: 15px;
            transition: all 0.3s ease;
        }
        
        .location-item:hover {
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
            transform: translateY(-2px);
        }
        
        .location-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        
        .source-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        
        .source-location {
            background: #28a745;
            color: white;
        }
        
        .source-image {
            background: #17a2b8;
            color: white;
        }
        
        .coordinates {
            font-family: 'Courier New', monospace;
            background: #f8f9fa;
            padding: 10px;
            border-radius: 5px;
            margin: 10px 0;
        }
        
        .map-link {
            color: #007bff;
            text-decoration: none;
            font-weight: 600;
        }
        
        .map-link:hover {
            text-decoration: underline;
        }
        
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #666;
        }
        
        .loading {
            text-align: center;
            padding: 40px;
            color: #666;
        }
        
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #007bff;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .alert {
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 10px;
            font-weight: 600;
        }
        
        .alert-success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        
        .alert-error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 20px;
                margin: 10px;
            }
            
            .controls {
                justify-content: center;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Location Information Dashboard</h1>
            <p>Monitor location data received from Flutter app</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-number" id="totalCount">0</div>
                <div class="stat-label">Total Location Records</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="recentCount">0</div>
                <div class="stat-label">Recent Locations (Memory)</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="imageCount">0</div>
                <div class="stat-label">Image Location Records</div>
            </div>
        </div>
        
        <div class="controls">
            <button class="btn" onclick="loadLocations()">Refresh</button>
            <button class="btn" onclick="clearRecentLocations()">Clear Memory</button>
            <button class="btn btn-danger" onclick="clearAllLogs()">Delete All Logs</button>
        </div>
        
        <div id="alertContainer"></div>
        
        <div class="location-list">
            <h3>Location Records</h3>
            <div id="locationList">
                <div class="loading">
                    <div class="spinner"></div>
                    <p>Loading location information...</p>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Load location information on page load
        document.addEventListener('DOMContentLoaded', function() {
            loadLocations();
            // Auto refresh every 10 seconds
            setInterval(loadLocations, 10000);
        });
        
        // Load location data
        async function loadLocations() {
            try {
                const response = await fetch('/locations-data');
                const data = await response.json();
                
                // Update statistics
                document.getElementById('totalCount').textContent = data.total_count;
                document.getElementById('recentCount').textContent = data.recent_locations.length;
                document.getElementById('imageCount').textContent = data.image_locations.length;
                
                // Render location list
                renderLocations([...data.recent_locations, ...data.image_locations]);
                
            } catch (error) {
                console.error('Failed to load location data:', error);
                showAlert('Failed to load location information.', 'error');
            }
        }
        
        // Render location list
        function renderLocations(locations) {
            const locationList = document.getElementById('locationList');
            
            if (locations.length === 0) {
                locationList.innerHTML = `
                    <div class="empty-state">
                        <div style="font-size: 4rem; margin-bottom: 20px;"></div>
                        <h3>No location records found</h3>
                        <p>Location data sent from Flutter app will be displayed here.</p>
                    </div>
                `;
                return;
            }
            
            // Sort by latest first
            locations.sort((a, b) => new Date(b.received_at) - new Date(a.received_at));
            
            locationList.innerHTML = locations.map(location => `
                <div class="location-item">
                    <div class="location-header">
                        <span class="source-badge ${location.source === 'location_api' ? 'source-location' : 'source-image'}">
                            ${location.source === 'location_api' ? 'Location API' : 'Image Upload'}
                        </span>
                        <small style="color: #666;">${formatDateTime(location.received_at)}</small>
                    </div>
                    
                    <div class="coordinates">
                        <strong>Latitude:</strong> ${location.latitude.toFixed(6)}<br>
                        <strong>Longitude:</strong> ${location.longitude.toFixed(6)}<br>
                        ${location.accuracy ? `<strong>Accuracy:</strong> ${location.accuracy}m<br>` : ''}
                        ${location.timestamp ? `<strong>Timestamp:</strong> ${location.timestamp}<br>` : ''}
                    </div>
                    
                    <div>
                        <a href="https://www.google.com/maps?q=${location.latitude},${location.longitude}" 
                           target="_blank" class="map-link">
                            View on Google Maps
                        </a>
                    </div>
                </div>
            `).join('');
        }
        
        // Format date time
        function formatDateTime(dateString) {
            const date = new Date(dateString);
            return date.toLocaleString('en-US', {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        }
        
        // Clear memory location data
        async function clearRecentLocations() {
            if (!confirm('Are you sure you want to delete all recent location data stored in memory?')) {
                return;
            }
            
            try {
                const response = await fetch('/clear-recent-locations', {
                    method: 'DELETE'
                });
                
                if (response.ok) {
                    showAlert('Memory location data has been cleared.', 'success');
                    loadLocations();
                } else {
                    throw new Error('Clear failed');
                }
            } catch (error) {
                showAlert('Failed to clear memory.', 'error');
            }
        }
        
        // Delete all logs
        async function clearAllLogs() {
            if (!confirm('Are you sure you want to delete all location log files? This action cannot be undone.')) {
                return;
            }
            
            try {
                const response = await fetch('/clear-all-logs', {
                    method: 'DELETE'
                });
                
                if (response.ok) {
                    showAlert('All logs have been deleted.', 'success');
                    loadLocations();
                } else {
                    throw new Error('Delete failed');
                }
            } catch (error) {
                showAlert('Failed to delete logs.', 'error');
            }
        }
        
        // Show alert
        function showAlert(message, type) {
            const alertContainer = document.getElementById('alertContainer');
            const alertClass = type === 'success' ? 'alert-success' : 'alert-error';
            
            const alertElement = document.createElement('div');
            alertElement.className = `alert ${alertClass}`;
            alertElement.textContent = message;
            
            alertContainer.appendChild(alertElement);
            
            setTimeout(() => {
                alertElement.remove();
            }, 3000);
        }
    </script>
</body>
</html>
"""
    return HTMLResponse(content=html_content)

@app.get("/locations-data")
async def get_locations_data():
    """Location data query API"""
    try:
        # Read today's log file
        today = datetime.now().strftime("%Y-%m-%d")
        log_file = os.path.join(LOCATION_LOG_DIR, f"locations_{today}.json")
        
        total_count = 0
        if os.path.exists(log_file):
            try:
                with open(log_file, 'r', encoding='utf-8') as f:
                    logs = json.load(f)
                    total_count = len(logs)
            except:
                total_count = 0
        
        return {
            "status": "success",
            "total_count": total_count,
            "recent_locations": recent_locations,
            "image_locations": image_locations
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to query location data: {str(e)}")

@app.delete("/clear-recent-locations")
async def clear_recent_locations():
    """Clear recent location data in memory"""
    global recent_locations, image_locations
    recent_locations.clear()
    image_locations.clear()
    return {"status": "success", "message": "Memory location data has been cleared"}

@app.delete("/clear-all-logs")
async def clear_all_logs():
    """Delete all location log files"""
    try:
        # Delete all JSON files in location_logs directory
        for filename in os.listdir(LOCATION_LOG_DIR):
            if filename.endswith('.json'):
                os.remove(os.path.join(LOCATION_LOG_DIR, filename))
        
        # Clear memory as well
        global recent_locations, image_locations
        recent_locations.clear()
        image_locations.clear()
        
        return {"status": "success", "message": "All logs have been deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete logs: {str(e)}")

@app.post("/location", response_model=LocationResponse)
async def receive_location(location: LocationData):
    try:
        # Location data processing logic
        print(f"[Location API] lat={location.latitude}, long={location.longitude}")
        print(f"   Accuracy: {location.accuracy}m, Time: {location.timestamp}")
        
        # Store in memory
        location_entry = {
            "id": str(uuid.uuid4()),
            "latitude": location.latitude,
            "longitude": location.longitude,
            "accuracy": location.accuracy,
            "timestamp": location.timestamp,
            "received_at": datetime.now().isoformat(),
            "source": "location_api"
        }
        recent_locations.append(location_entry)
        
        # Keep maximum 50 items in memory
        if len(recent_locations) > 50:
            recent_locations.pop(0)
        
        # Save to file
        save_location_to_file(location.dict(), "location_api")
        
        return LocationResponse(
            status="success",
            message="Location information received successfully",
            received_data=location
        )
    except Exception as e:
        print(f"Location processing error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")

@app.post("/upload-image", response_model=ImageUploadResponse)
async def upload_image(
    image: UploadFile = File(...),
    latitude: Optional[str] = Form(None),
    longitude: Optional[str] = Form(None),
    timestamp: Optional[str] = Form(None)
):
    try:
        # Validate file extension
        allowed_extensions = {".jpg", ".jpeg", ".png", ".gif", ".bmp"}
        file_extension = os.path.splitext(image.filename)[1].lower()
        
        if file_extension not in allowed_extensions:
            raise HTTPException(
                status_code=400, 
                detail=f"Unsupported file format. Allowed formats: {', '.join(allowed_extensions)}"
            )
        
        # Generate unique filename
        unique_filename = f"{uuid.uuid4()}{file_extension}"
        file_path = os.path.join(UPLOAD_DIR, unique_filename)
        
        # Save file
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)
        
        # Process location information
        location_info = None
        if latitude and longitude:
            location_info = {
                "latitude": float(latitude),
                "longitude": float(longitude),
                "timestamp": timestamp
            }
            
            print(f"📷 [Image Upload] File: {unique_filename}")
            print(f"   Location: lat={latitude}, long={longitude}")
            print(f"   Time: {timestamp}")
            
            # Store in memory
            location_entry = {
                "id": str(uuid.uuid4()),
                "latitude": float(latitude),
                "longitude": float(longitude),
                "accuracy": None,
                "timestamp": timestamp,
                "received_at": datetime.now().isoformat(),
                "source": "image_upload",
                "filename": unique_filename
            }
            image_locations.append(location_entry)
            
            # Keep maximum 50 items in memory
            if len(image_locations) > 50:
                image_locations.pop(0)
            
            # Save to file
            save_location_to_file(location_info, "image_upload")
        
        # Generate image URL
        image_url = f"/images/{unique_filename}"
        
        print(f"✅ Image upload completed: {image_url}")
        
        return ImageUploadResponse(
            status="success",
            message="Image uploaded successfully",
            filename=unique_filename,
            image_url=image_url,
            location=location_info
        )
        
    except Exception as e:
        print(f"❌ Image upload error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Image upload failed: {str(e)}")

@app.get("/gallery", response_class=HTMLResponse)
async def show_gallery():
    """Image gallery web page"""
    html_content = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Image Gallery</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
        }
        
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        
        .header h1 {
            color: #333;
            font-size: 2.5rem;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.1);
        }
        
        .header p {
            color: #666;
            font-size: 1.1rem;
        }
        
        .nav-links {
            text-align: center;
            margin-bottom: 20px;
        }
        
        .nav-link {
            display: inline-block;
            background: #007bff;
            color: white;
            padding: 10px 20px;
            border-radius: 20px;
            text-decoration: none;
            margin: 0 10px;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .nav-link:hover {
            background: #0056b3;
            transform: translateY(-2px);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📸 Image Gallery</h1>
            <p>View and manage uploaded images</p>
        </div>
        
        <div class="nav-links">
            <a href="/locations" class="nav-link">📍 Location Dashboard</a>
            <a href="/gallery" class="nav-link">📷 Image Gallery</a>
        </div>
        
        <p style="text-align: center; color: #666; margin-top: 30px;">
            Gallery functionality remains the same. You can check coordinates sent from Flutter on the Location Dashboard page.
        </p>
    </div>
</body>
</html>
"""
    return HTMLResponse(content=html_content)

@app.get("/images-list")
async def list_uploaded_images():
    """Query uploaded image list"""
    try:
        images = []
        for filename in os.listdir(UPLOAD_DIR):
            if filename.lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.bmp')):
                file_path = os.path.join(UPLOAD_DIR, filename)
                file_size = os.path.getsize(file_path)
                created_time = datetime.fromtimestamp(os.path.getctime(file_path))
                
                images.append({
                    "filename": filename,
                    "url": f"/images/{filename}",
                    "size": file_size,
                    "created_at": created_time.isoformat()
                })
        
        return {
            "status": "success",
            "count": len(images),
            "images": sorted(images, key=lambda x: x["created_at"], reverse=True)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to query image list: {str(e)}")

@app.delete("/images/{filename}")
async def delete_image(filename: str):
    """Delete specific image"""
    try:
        file_path = os.path.join(UPLOAD_DIR, filename)
        
        if not os.path.exists(file_path):
            raise HTTPException(status_code=404, detail="Image not found")
        
        os.remove(file_path)
        
        return {
            "status": "success",
            "message": f"Image {filename} has been deleted"
        }
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Image not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete image: {str(e)}")

@app.get("/")
async def root():
    return {
        "message": "Location API Server is running",
        "endpoints": {
            "GET /": "Server information",
            "GET /locations": "Location information web page",
            "GET /locations-data": "Location data query API",
            "GET /gallery": "Image gallery for web browser",
            "POST /location": "Send location data",
            "POST /upload-image": "Upload image (with optional location data)",
            "GET /images-list": "List uploaded images",
            "GET /images/{filename}": "Query image file",
            "DELETE /images/{filename}": "Delete image",
            "DELETE /clear-recent-locations": "Clear memory location data",
            "DELETE /clear-all-logs": "Delete all location logs"
        },
        "web_pages": {
            "http://localhost:8000/locations": "Location information dashboard",
            "http://localhost:8000/gallery": "Image gallery"
        }
    }

if __name__ == "__main__":
    print("="*60)
    print("Location API Server Starting")
    print("="*60)
    print(f"Upload directory: {os.path.abspath(UPLOAD_DIR)}")
    print(f"Log directory: {os.path.abspath(LOCATION_LOG_DIR)}")
    print("")
    print("Web Interface:")
    print("   Server info: http://localhost:8000")
    print("   Location dashboard: http://localhost:8000/locations")
    print("   Image gallery: http://localhost:8000/gallery")
    print("")
    print("API Endpoints:")
    print("   POST /location - Receive location data")
    print("   POST /upload-image - Image upload")
    print("   GET /locations-data - Query location data")
    print("")
    print("To check coordinates from Flutter:")
    print("   1. Access http://localhost:8000/locations in browser")
    print("   2. Send location from Flutter app")
    print("   3. View real-time location information")
    print("="*60)
    uvicorn.run(app, host="0.0.0.0", port=8000)