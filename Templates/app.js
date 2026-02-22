const tooltip = document.getElementById('tooltip');

document.querySelectorAll('[data-tooltip]').forEach(function(el) {
    el.addEventListener('mouseenter', function(e) {
        const text = this.getAttribute('data-tooltip');
        const rect = this.getBoundingClientRect();
        tooltip.textContent = text;
        tooltip.style.left = (rect.right + 10) + 'px';
        tooltip.style.top = (rect.top + rect.height / 2) + 'px';
        tooltip.style.transform = 'translateY(-50%)';
        tooltip.classList.add('show');
    });
    el.addEventListener('mouseleave', function() {
        tooltip.classList.remove('show');
    });
});

function toggleSelect(event, checkbox) {
    event.stopPropagation();
    var item = checkbox.closest('.media-item');
    if (checkbox.checked) {
        item.classList.add('selected');
    } else {
        item.classList.remove('selected');
    }
    updateSelectedCount();
}

function updateSelectedCount() {
    var folderCount = document.querySelectorAll('.folder-checkbox:checked').length;
    var fileCount = 0;
    
    document.querySelectorAll('.folder-card').forEach(function(card) {
        var folderCheckbox = card.querySelector('.folder-checkbox');
        var mediaGrid = card.querySelector('.media-grid');
        
        if (folderCheckbox.checked) {
            if (mediaGrid.children.length > 0) {
                fileCount += mediaGrid.querySelectorAll('.media-checkbox:checked').length;
            } else {
                var files = JSON.parse(card.dataset.files);
                fileCount += files.length;
            }
        } else {
            fileCount += mediaGrid.querySelectorAll('.media-checkbox:checked').length;
        }
    });
    
    var countDiv = document.getElementById('selectedCount');
    
    if (folderCount === 0 && fileCount === 0) {
        countDiv.innerHTML = '0 ausgewählt';
    } else if (folderCount > 0 && fileCount === 0) {
        countDiv.innerHTML = folderCount + ' Ordner';
    } else if (folderCount === 0 && fileCount > 0) {
        countDiv.innerHTML = fileCount + ' Dateien';
    } else {
        countDiv.innerHTML = folderCount + ' Ordner<br>' + fileCount + ' Dateien';
    }
}

function updateActionBarVisibility() {
    var hasExpandedFolders = document.querySelectorAll('.folder-card.expanded').length > 0;
    var hasCheckedFolders = document.querySelectorAll('.folder-checkbox:checked').length > 0;
    
    if (hasExpandedFolders || hasCheckedFolders) {
        document.getElementById('floatingActionBar').classList.add('show');
    } else {
        document.getElementById('floatingActionBar').classList.remove('show');
    }
}

function getSelectedItems() {
    var paths = [];
    
    document.querySelectorAll('.folder-card').forEach(function(card) {
        var folderCheckbox = card.querySelector('.folder-checkbox');
        var folderPath = card.dataset.path;
        var mediaGrid = card.querySelector('.media-grid');
        
        if (folderCheckbox.checked) {
            if (mediaGrid.children.length > 0) {
                mediaGrid.querySelectorAll('.media-checkbox:checked').forEach(function(cb) {
                    paths.push(cb.closest('.media-item').dataset.filepath);
                });
            } else {
                var files = JSON.parse(card.dataset.files);
                files.forEach(function(file) {
                    var filePath = folderPath === '.' ? file : folderPath + '/' + file;
                    paths.push(filePath);
                });
            }
        } else {
            mediaGrid.querySelectorAll('.media-checkbox:checked').forEach(function(cb) {
                paths.push(cb.closest('.media-item').dataset.filepath);
            });
        }
    });
    
    return paths;
}

function toggleFolderSelection(checkbox) {
    var folderCard = checkbox.closest('.folder-card');
    var mediaGrid = folderCard.querySelector('.media-grid');
    
    var mediaCheckboxes = mediaGrid.querySelectorAll('.media-checkbox');
    
    mediaCheckboxes.forEach(function(cb) {
        cb.checked = checkbox.checked;
        var item = cb.closest('.media-item');
        if (cb.checked) {
            item.classList.add('selected');
        } else {
            item.classList.remove('selected');
        }
    });
    
    updateSelectedCount();



    updateActionBarVisibility();
}

function selectAll() {
    // Alle Folder-Checkboxen
    document.querySelectorAll('.folder-checkbox').forEach(function(fcb) {
        fcb.checked = true;
    });
    
    // Alle Media-Checkboxen
    document.querySelectorAll('.media-checkbox').forEach(function(cb) {
        cb.checked = true;
        cb.closest('.media-item').classList.add('selected');
    });
    
    updateSelectedCount();
    updateActionBarVisibility();
}

function selectNone() {
    // Alle Folder-Checkboxen
    document.querySelectorAll('.folder-checkbox').forEach(function(fcb) {
        fcb.checked = false;
    });
    
    // Alle Media-Checkboxen
    document.querySelectorAll('.media-checkbox').forEach(function(cb) {
        cb.checked = false;
        cb.closest('.media-item').classList.remove('selected');
    });
    
    updateSelectedCount();
    updateActionBarVisibility();
}

function invertSelection() {
    // Alle Folder-Checkboxen invertieren
    document.querySelectorAll('.folder-checkbox').forEach(function(fcb) {
        fcb.checked = !fcb.checked;
    });
    
    // Alle Media-Checkboxen invertieren
    document.querySelectorAll('.media-checkbox').forEach(function(cb) {
        cb.checked = !cb.checked;
        var item = cb.closest('.media-item');
        if (cb.checked) {
            item.classList.add('selected');
        } else {
            item.classList.remove('selected');
        }
    });
    
    updateSelectedCount();
    updateActionBarVisibility();
}

async function deleteSelected() {
    var paths = getSelectedItems();
    
    if (paths.length === 0) {
        alert('Keine Dateien ausgewählt!');
        return;
    }
    
    if (!confirm(paths.length + ' Datei(en) wirklich löschen?')) {
        return;
    }
    
    try {
        var response = await fetch('/delete-files', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ paths: paths })
        });
        
        var result = await response.json();
        
        if (result.success) {
            document.querySelectorAll('.folder-card').forEach(function(card) {
                var folderCheckbox = card.querySelector('.folder-checkbox');
                var mediaGrid = card.querySelector('.media-grid');
                
                if (folderCheckbox.checked && mediaGrid.children.length === 0) {
                    card.remove();
                } else {
                    mediaGrid.querySelectorAll('.media-checkbox:checked').forEach(function(cb) {
                        cb.closest('.media-item').remove();
                    });
                    folderCheckbox.checked = false;
                }
            });
            
            updateSelectedCount();
            updateActionBarVisibility();
            alert('✓ ' + result.deletedCount + ' Datei(en) gelöscht');
        } else {
            alert('❌ Fehler: ' + (result.error || 'Unbekannt'));
        }
    } catch (err) {
        alert('❌ Fehler: ' + err.message);
    }
}

function toggleFolder(header) {
    const card = header.closest('.folder-card');
    const grid = card.querySelector('.media-grid');
    const isExpanded = card.classList.contains('expanded');
    
    if (isExpanded) {
        // Ordner schließen
        grid.style.display = 'none';
        card.classList.remove('expanded');
        
        updateActionBarVisibility();
    } else {
        // ACCORDION: Schließe alle anderen Ordner
        document.querySelectorAll('.folder-card.expanded').forEach(function(otherCard) {
            if (otherCard !== card) {
                otherCard.querySelector('.media-grid').style.display = 'none';
                otherCard.classList.remove('expanded');
            }
        });
        
        // Ordner öffnen
        card.classList.add('expanded');
        
        // Auto-Scroll zum geöffneten Ordner
        setTimeout(function() {
            header.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }, 100);
        
        // Trigger Background-Job für Thumbnail-Generierung
        triggerFolderThumbnailJob(card);
        
        if (grid.children.length === 0) {
            const files = JSON.parse(card.dataset.files);
            const folderPath = card.dataset.path;
            
            // Check ob Folder-Checkbox aktiv ist
            const folderCheckbox = card.querySelector('.folder-checkbox');
            const shouldSelectAll = folderCheckbox && folderCheckbox.checked;
            
            files.forEach(function(file) {
                const isVideo = /\.(mp4|mov|avi|mkv|webm|m4v|wmv|flv|mpg|mpeg|3gp)$/i.test(file);
                const filePath = folderPath === '.' ? file : folderPath + '/' + file;
                const imgUrl = '/img?path=' + encodeURIComponent(filePath);
                const item = document.createElement('div');
                item.className = 'media-item';
                item.dataset.filepath = filePath;
                
                // Wenn Folder-Checkbox aktiv → Media auch markieren
                const checkedAttr = shouldSelectAll ? ' checked' : '';
                const selectedClass = shouldSelectAll ? ' selected' : '';
                
                item.className = 'media-item' + selectedClass;
                item.innerHTML = '<input type="checkbox" class="media-checkbox"' + checkedAttr + ' onclick="toggleSelect(event, this)">' +
                                '<img src="' + imgUrl + '" alt="' + file + '" loading="lazy">' +
                                (isVideo ? '<span class="video-badge">▶ VIDEO</span>' : '');
                grid.appendChild(item);
            });
            
            // Update Counter falls Medien markiert wurden
            if (shouldSelectAll) {
                updateSelectedCount();
            }
        }
        grid.style.display = 'grid';
        
        updateActionBarVisibility();
    }
}

async function changeRoot() {
    try {
        const response = await fetch('/changeroot', { method: 'POST' });
        const result = await response.json();
        if (result.cancelled) return;
        if (result.ok) {
            location.reload();
        } else {
            alert('Fehler: ' + (result.error || 'Unbekannter Fehler'));
        }
    } catch (err) {
        console.error('Fehler:', err);
    }
}

async function shutdownServer() {
    if (!confirm('Server wirklich beenden?')) return;
    try {
        await fetch('/shutdown', { method: 'POST' });
        document.body.innerHTML = '<div style="display:flex;flex-direction:column;gap:20px;align-items:center;justify-content:center;min-height:100vh;font-size:24px;color:#2d3748;"><div style="font-size:60px;">✓</div><div>Server beendet!</div></div>';
    } catch (err) {
        console.log('Server beendet');
    }
}

async function checkServerStatus() {
    const btn = document.getElementById('statusBtn');
    try {
        await fetch('/ping');
        btn.classList.remove('offline');
        btn.setAttribute('data-tooltip', 'Server läuft');
    } catch {
        btn.classList.add('offline');
        btn.setAttribute('data-tooltip', 'Server offline');
    }
}

setInterval(checkServerStatus, 2000);
checkServerStatus();

function openTools() {
    document.getElementById('toolsOverlay').classList.add('show');
}

function closeTools() {
    document.getElementById('toolsOverlay').classList.remove('show');
    document.getElementById('statsResult').innerHTML = '';
    document.getElementById('thumbsList').innerHTML = '';
}

async function getCacheStats() {
    var resultDiv = document.getElementById('statsResult');
    resultDiv.innerHTML = '<div class="overlay-result">⏳ Berechne Statistik...</div>';
    
    try {
        var response = await fetch('/tools/cache-stats');
        var result = await response.json();
        
        if (result.success) {
            resultDiv.innerHTML = '<div class="overlay-result success">' +
                '<div style="font-weight: 600; margin-bottom: 8px;">📊 Cache-Statistik</div>' +
                '<div>📁 .thumbs Ordner: ' + result.data.ThumbsDirectories + '</div>' +
                '<div>🖼️ Thumbnail-Dateien: ' + result.data.ThumbnailFiles + '</div>' +
                '<div>💾 Gesamtgröße: ' + result.data.TotalSizeFormatted + '</div>' +
                '</div>';
        } else {
            resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + (result.error || 'Fehler') + '</div>';
        }
    } catch (err) {
        resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + err.message + '</div>';
    }
}

async function listThumbs() {
    var listDiv = document.getElementById('thumbsList');
    listDiv.innerHTML = '<div class="overlay-result">⏳ Lade Liste...</div>';
    
    try {
        var response = await fetch('/tools/list-thumbs');
        var result = await response.json();
        
        if (!result.success) {
            listDiv.innerHTML = '<div class="overlay-result error">❌ ' + (result.error || 'Fehler') + '</div>';
            return;
        }
        
        if (result.data.length === 0) {
            listDiv.innerHTML = '<div class="overlay-result">Keine .thumbs Ordner gefunden</div>';
            return;
        }
        
        var itemsHtml = result.data.map(function(item) {
            return '<div class="thumbs-item">' +
                '<input type="checkbox" class="thumbs-checkbox" data-path="' + item.Path + '">' +
                '<div class="thumbs-info">' +
                '<div class="thumbs-path">📁 ' + item.RelativePath + '</div>' +
                '<div class="thumbs-details">' + item.FileCount + ' Dateien, ' + item.SizeFormatted + '</div>' +
                '</div></div>';
        }).join('');
        
        listDiv.innerHTML = '<div class="thumbs-list">' + itemsHtml + '</div>' +
            '<div class="list-actions">' +
            '<button class="list-action-btn" onclick="selectAllThumbs()">☑ Alle auswählen</button>' +
            '<button class="list-action-btn" onclick="deselectAllThumbs()">☐ Alle abwählen</button>' +
            '<button class="list-action-btn danger" onclick="deleteSelectedThumbs()">🗑️ Ausgewählte löschen</button>' +
            '</div><div id="deleteSelectedResult"></div>';
    } catch (err) {
        listDiv.innerHTML = '<div class="overlay-result error">❌ ' + err.message + '</div>';
    }
}

function selectAllThumbs() {
    document.querySelectorAll('.thumbs-checkbox').forEach(function(cb) { cb.checked = true; });
}

function deselectAllThumbs() {
    document.querySelectorAll('.thumbs-checkbox').forEach(function(cb) { cb.checked = false; });
}

async function deleteSelectedThumbs() {
    var checkboxes = document.querySelectorAll('.thumbs-checkbox:checked');
    if (checkboxes.length === 0) {
        alert('Keine Ordner ausgewählt!');
        return;
    }
    
    var paths = Array.from(checkboxes).map(function(cb) { return cb.dataset.path; });
    if (!confirm(paths.length + ' Ordner wirklich löschen?')) return;
    
    var resultDiv = document.getElementById('deleteSelectedResult');
    resultDiv.innerHTML = '<div class="overlay-result">⏳ Lösche...</div>';
    
    try {
        var response = await fetch('/tools/delete-selected', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ paths: paths })
        });
        var result = await response.json();
        
        if (result.success) {
            resultDiv.innerHTML = '<div class="overlay-result success">✓ ' + 
                result.data.DeletedCount + ' Ordner gelöscht (' + 
                (result.data.DeletedSize / 1024 / 1024).toFixed(2) + ' MB)</div>';
            setTimeout(function() { listThumbs(); }, 1000);
        } else {
            resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + result.error + '</div>';
        }
    } catch (err) {
        resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + err.message + '</div>';
    }
}

async function deleteAllThumbs() {
    if (!confirm('ALLE .thumbs Ordner wirklich löschen?\n\nDies kann nicht rückgängig gemacht werden!')) return;
    if (!confirm('Bist du sicher? Dies löscht ALLE Thumbnails im gesamten Root!')) return;
    
    try {
        var response = await fetch('/tools/delete-all-thumbs', { method: 'POST' });
        var result = await response.json();
        
        if (result.success) {
            alert('✓ ' + result.data.DeletedCount + ' Ordner gelöscht\n' + 
                (result.data.DeletedSize / 1024 / 1024).toFixed(2) + ' MB freigegeben');
            closeTools();
        } else {
            alert('❌ Fehler: ' + (result.error || 'Unbekannter Fehler'));
        }
    } catch (err) {
        alert('❌ Fehler: ' + err.message);
    }
}

var cacheRebuildStatusInterval = null;

async function startCacheRebuild() {
    var resultDiv = document.getElementById('cacheRebuildResult');
    resultDiv.innerHTML = '<div class="overlay-result">⏳ Starte Background-Job...</div>';
    
    try {
        var response = await fetch('/tools/cache/start', { method: 'POST' });
        var result = await response.json();
        
        if (result.success) {
            resultDiv.innerHTML = '<div class="overlay-result success">✓ Job gestartet (ID: ' + result.data.JobId + ')</div>';
            
            if (cacheRebuildStatusInterval) clearInterval(cacheRebuildStatusInterval);
            cacheRebuildStatusInterval = setInterval(updateCacheRebuildStatus, 2000);
            updateCacheRebuildStatus();
        } else {
            resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + (result.error || 'Fehler') + '</div>';
        }
    } catch (err) {
        resultDiv.innerHTML = '<div class="overlay-result error">❌ ' + err.message + '</div>';
    }
}

async function updateCacheRebuildStatus() {
    try {
        var response = await fetch('/tools/cache/status');
        var result = await response.json();
        
        if (!result.success) return;
        
        var data = result.data;
        var statusDiv = document.getElementById('cacheRebuildStatus');
        
        if (data.Status === 'NotStarted') {
            statusDiv.innerHTML = '<div class="overlay-result">Kein Job aktiv</div>';
            if (cacheRebuildStatusInterval) clearInterval(cacheRebuildStatusInterval);
            return;
        }
        
        if (data.Status === 'Running') {
            statusDiv.innerHTML = 
                '<div class="overlay-result">' +
                '<div style="font-weight: 600; margin-bottom: 8px;">⏳ Cache-Rebuild läuft...</div>' +
                '<div class="progress-bar"><div class="progress-fill" style="width: ' + data.Progress + '%"></div></div>' +
                '<div style="margin-top: 8px;">' + data.Progress + '% (' + data.ProcessedFolders + ' / ' + data.TotalFolders + ' Ordner)</div>' +
                '<div>✓ Aktualisiert: ' + data.UpdatedFolders + ' | ✓ Valide: ' + data.ValidFolders + '</div>' +
                '<div style="font-size: 12px; color: #718096; margin-top: 4px;">Aktuell: ' + data.CurrentFolder + '</div>' +
                '<div style="font-size: 12px; color: #718096;">Laufzeit: ' + data.Duration + 's</div>' +
                '<button class="list-action-btn danger" onclick="stopCacheRebuild()" style="margin-top: 8px;">⏹ Job stoppen</button>' +
                '</div>';
        }
        else if (data.Status === 'Completed') {
            statusDiv.innerHTML =
                '<div class="overlay-result success">' +
                '<div style="font-weight: 600; margin-bottom: 8px;">✓ Cache-Rebuild abgeschlossen!</div>' +
                '<div>' + data.TotalFolders + ' Ordner verarbeitet</div>' +
                '<div>✓ Aktualisiert: ' + data.UpdatedFolders + ' | ✓ Valide: ' + data.ValidFolders + '</div>' +
                '<div style="font-size: 12px; color: #718096;">Dauer: ' + data.Duration + 's</div>' +
                '</div>';
            if (cacheRebuildStatusInterval) clearInterval(cacheRebuildStatusInterval);
        }
        else if (data.Status === 'Error') {
            statusDiv.innerHTML = '<div class="overlay-result error">❌ Fehler: ' + (data.Error || 'Unbekannt') + '</div>';
            if (cacheRebuildStatusInterval) clearInterval(cacheRebuildStatusInterval);
        }
    } catch (err) {
        console.error('Status-Update Fehler:', err);
    }
}

async function stopCacheRebuild() {
    try {
        var response = await fetch('/tools/cache/stop', { method: 'POST' });
        var result = await response.json();
        
        if (result.success && result.data.Stopped) {
            if (cacheRebuildStatusInterval) clearInterval(cacheRebuildStatusInterval);
            document.getElementById('cacheRebuildStatus').innerHTML = '<div class="overlay-result">Job gestoppt</div>';
        }
    } catch (err) {
        console.error('Stop Fehler:', err);
    }
}

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closeTools();
});

document.getElementById('toolsOverlay').addEventListener('click', function(e) {
    if (e.target === this) closeTools();
});

function toggleCategory(header) {
    var category = header.closest('.settings-category');
    var isExpanded = category.classList.contains('expanded');
    
    // Schließe alle anderen Kategorien
    document.querySelectorAll('.settings-category.expanded').forEach(function(cat) {
        if (cat !== category) {
            cat.classList.remove('expanded');
        }
    });
    
    // Toggle aktuelle Kategorie
    if (isExpanded) {
        category.classList.remove('expanded');
    } else {
        category.classList.add('expanded');
        
        // Scroll zum Kategorie-Header
        setTimeout(function() {
            header.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }, 100);
    }
}

function openSettings() {
    loadSettings();
    document.getElementById('settingsOverlay').classList.add('show');
}

function closeSettings() {
    document.getElementById('settingsOverlay').classList.remove('show');
}

async function loadSettings() {
    try {
        var response = await fetch('/settings/get');
        var config = await response.json();
        
        document.getElementById('setting-server-port').value = config.Server.Port;
        document.getElementById('setting-server-host').value = config.Server.Host;
        document.getElementById('setting-server-autoopen').checked = config.Server.AutoOpenBrowser;
        
        document.getElementById('setting-media-images').value = config.Media.ImageExtensions.join(';');
        document.getElementById('setting-media-videos').value = config.Media.VideoExtensions.join(';');
        
        document.getElementById('setting-video-quality').value = config.Video.ThumbnailQuality;
        document.getElementById('setting-video-autoconvert').checked = config.Video.EnableAutoConversion;
        document.getElementById('setting-video-hls').checked = config.Video.UseHLS;
        document.getElementById('setting-video-hlssegment').value = config.Video.HLSSegmentDuration;
        document.getElementById('setting-video-codec').value = config.Video.PreferredCodec;
        document.getElementById('setting-video-preset').value = config.Video.ConversionPreset;
        document.getElementById('setting-video-thumbcount').value = config.Video.ThumbnailCount;
        document.getElementById('setting-video-thumbfps').value = config.Video.ThumbnailFPS;
        document.getElementById('setting-video-gifpreview').checked = config.Video.PreviewAsGIF;
        document.getElementById('setting-video-gifduration').value = config.Video.GIFDuration;
        document.getElementById('setting-video-gifframerate').value = config.Video.GIFFrameRate;
        document.getElementById('setting-video-gifloop').checked = config.Video.GIFLoop;
        document.getElementById('setting-video-thumbstart').value = config.Video.ThumbnailStartPercent;
        document.getElementById('setting-video-thumbend').value = config.Video.ThumbnailEndPercent;
        
        document.getElementById('setting-ui-theme').value = config.UI.Theme;
        document.getElementById('setting-ui-defaultsize').value = config.UI.DefaultThumbSize || 'medium';
        document.getElementById('setting-ui-thumbsize').value = config.UI.ThumbnailSize;
        document.getElementById('setting-ui-columns').value = config.UI.GridColumns;
        document.getElementById('setting-ui-previewcount').value = config.UI.PreviewThumbnailCount;
        document.getElementById('setting-ui-showmetadata').checked = config.UI.ShowVideoMetadata;
        document.getElementById('setting-ui-showcodec').checked = config.UI.ShowVideoCodec;
        document.getElementById('setting-ui-showduration').checked = config.UI.ShowVideoDuration;
        document.getElementById('setting-ui-showcompat').checked = config.UI.ShowBrowserCompatibility;
        
        document.getElementById('setting-perf-parallel').checked = config.Performance.UseParallelProcessing;
        document.getElementById('setting-perf-maxjobs').value = config.Performance.MaxParallelJobs;
        document.getElementById('setting-perf-cache').checked = config.Performance.CacheThumbnails;
        document.getElementById('setting-perf-lazy').checked = config.Performance.LazyLoading;
        document.getElementById('setting-perf-timeout').value = config.Performance.DeleteJobTimeout;
        
        document.getElementById('setting-file-recycle').checked = config.FileOperations.UseRecycleBin;
        document.getElementById('setting-file-confirm').checked = config.FileOperations.ConfirmDelete;
        document.getElementById('setting-file-move').checked = config.FileOperations.EnableMove;
        document.getElementById('setting-file-flatten').checked = config.FileOperations.EnableFlattenAndMove;
        document.getElementById('setting-file-range').checked = config.FileOperations.RangeRequestSupport;
        
        document.getElementById('setting-cache-scan').checked = config.Cache.UseScanCache;
        document.getElementById('setting-cache-folder').value = config.Cache.CacheFolder;
        document.getElementById('setting-cache-videometa').checked = config.Cache.VideoMetadataCache;
        
        document.getElementById('setting-feat-archive').checked = config.Features.ArchiveExtraction;
        document.getElementById('setting-feat-archiveext').value = config.Features.ArchiveExtensions.join(';');
        document.getElementById('setting-feat-thumbpre').checked = config.Features.VideoThumbnailPreGeneration;
        document.getElementById('setting-feat-lazyconv').checked = config.Features.LazyVideoConversion;
        document.getElementById('setting-feat-vlc').checked = config.Features.OpenInVLC;
        document.getElementById('setting-feat-collapse').checked = config.Features.CollapsibleFolders;
        document.getElementById('setting-feat-lightbox').checked = config.Features.LightboxViewer;
        document.getElementById('setting-feat-keyboard').checked = config.Features.KeyboardNavigation;
    } catch (err) {
        alert('Fehler beim Laden der Einstellungen: ' + err.message);
    }
}

async function saveSettings() {
    try {
        var settings = {
            Server: {
                Port: parseInt(document.getElementById('setting-server-port').value),
                Host: document.getElementById('setting-server-host').value,
                AutoOpenBrowser: document.getElementById('setting-server-autoopen').checked
            },
            Media: {
                ImageExtensions: document.getElementById('setting-media-images').value.split(';').map(function(s) { return s.trim(); }).filter(Boolean),
                VideoExtensions: document.getElementById('setting-media-videos').value.split(';').map(function(s) { return s.trim(); }).filter(Boolean)
            },
            Video: {
                ThumbnailQuality: parseInt(document.getElementById('setting-video-quality').value),
                EnableAutoConversion: document.getElementById('setting-video-autoconvert').checked,
                UseHLS: document.getElementById('setting-video-hls').checked,
                HLSSegmentDuration: parseInt(document.getElementById('setting-video-hlssegment').value),
                PreferredCodec: document.getElementById('setting-video-codec').value,
                ConversionPreset: document.getElementById('setting-video-preset').value,
                ThumbnailCount: parseInt(document.getElementById('setting-video-thumbcount').value),
                ThumbnailFPS: parseInt(document.getElementById('setting-video-thumbfps').value),
                PreviewAsGIF: document.getElementById('setting-video-gifpreview').checked,
                GIFDuration: parseInt(document.getElementById('setting-video-gifduration').value),
                GIFFrameRate: parseInt(document.getElementById('setting-video-gifframerate').value),
                GIFLoop: document.getElementById('setting-video-gifloop').checked,
                ThumbnailStartPercent: parseInt(document.getElementById('setting-video-thumbstart').value),
                ThumbnailEndPercent: parseInt(document.getElementById('setting-video-thumbend').value)
            },
            UI: {
                Theme: document.getElementById('setting-ui-theme').value,
                DefaultThumbSize: document.getElementById('setting-ui-defaultsize').value,
                ThumbnailSize: parseInt(document.getElementById('setting-ui-thumbsize').value),
                GridColumns: parseInt(document.getElementById('setting-ui-columns').value),
                PreviewThumbnailCount: parseInt(document.getElementById('setting-ui-previewcount').value),
                ShowVideoMetadata: document.getElementById('setting-ui-showmetadata').checked,
                ShowVideoCodec: document.getElementById('setting-ui-showcodec').checked,
                ShowVideoDuration: document.getElementById('setting-ui-showduration').checked,
                ShowBrowserCompatibility: document.getElementById('setting-ui-showcompat').checked
            },
            Performance: {
                UseParallelProcessing: document.getElementById('setting-perf-parallel').checked,
                MaxParallelJobs: parseInt(document.getElementById('setting-perf-maxjobs').value),
                CacheThumbnails: document.getElementById('setting-perf-cache').checked,
                LazyLoading: document.getElementById('setting-perf-lazy').checked,
                DeleteJobTimeout: parseInt(document.getElementById('setting-perf-timeout').value)
            },
            FileOperations: {
                UseRecycleBin: document.getElementById('setting-file-recycle').checked,
                ConfirmDelete: document.getElementById('setting-file-confirm').checked,
                EnableMove: document.getElementById('setting-file-move').checked,
                EnableFlattenAndMove: document.getElementById('setting-file-flatten').checked,
                RangeRequestSupport: document.getElementById('setting-file-range').checked
            },
            Cache: {
                UseScanCache: document.getElementById('setting-cache-scan').checked,
                CacheFolder: document.getElementById('setting-cache-folder').value,
                VideoMetadataCache: document.getElementById('setting-cache-videometa').checked
            },
            Features: {
                ArchiveExtraction: document.getElementById('setting-feat-archive').checked,
                ArchiveExtensions: document.getElementById('setting-feat-archiveext').value.split(';').map(function(s) { return s.trim(); }).filter(Boolean),
                VideoThumbnailPreGeneration: document.getElementById('setting-feat-thumbpre').checked,
                LazyVideoConversion: document.getElementById('setting-feat-lazyconv').checked,
                OpenInVLC: document.getElementById('setting-feat-vlc').checked,
                CollapsibleFolders: document.getElementById('setting-feat-collapse').checked,
                LightboxViewer: document.getElementById('setting-feat-lightbox').checked,
                KeyboardNavigation: document.getElementById('setting-feat-keyboard').checked
            }
        };
        
        var response = await fetch('/settings/save', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(settings)
        });
        
        var result = await response.json();
        
        if (result.success) {
            alert('✓ Einstellungen gespeichert!\n\nServer wird neu gestartet...');
            location.reload();
        } else {
            alert('❌ Fehler beim Speichern: ' + (result.error || 'Unbekannt'));
        }
    } catch (err) {
        alert('❌ Fehler: ' + err.message);
    }
}

async function resetSettings() {
    if (!confirm('Alle Einstellungen auf Standardwerte zurücksetzen?')) return;
    
    try {
        var response = await fetch('/settings/reset', { method: 'POST' });
        var result = await response.json();
        
        if (result.success) {
            alert('✓ Einstellungen auf Standard zurückgesetzt!\n\nServer wird neu gestartet...');
            location.reload();
        } else {
            alert('❌ Fehler: ' + (result.error || 'Unbekannt'));
        }
    } catch (err) {
        alert('❌ Fehler: ' + err.message);
    }
}

document.getElementById('settingsOverlay').addEventListener('click', function(e) {
    if (e.target === this) closeSettings();
});

var baseThumbnailSize = 200;

function setThumbSize(size) {
    document.querySelectorAll('.size-btn').forEach(function(btn) {
        btn.classList.remove('active');
    });
    
    var sizeMultiplier = {
        'small': 0.75,
        'medium': 1,
        'large': 1.5
    };
    
    var pixelSize = Math.round(baseThumbnailSize * sizeMultiplier[size]);
    
    document.querySelector('.size-' + size).classList.add('active');
    
    var style = document.querySelector('style.dynamic-thumb-size');
    if (!style) {
        style = document.createElement('style');
        style.className = 'dynamic-thumb-size';
        document.head.appendChild(style);
    }
    
    style.textContent = '.media-grid { grid-template-columns: repeat(auto-fill, minmax(' + pixelSize + 'px, 1fr)); }';
}

async function initThumbSize() {
    try {
        var response = await fetch('/settings/get');
        var config = await response.json();
        baseThumbnailSize = config.UI.ThumbnailSize || 200;
        var defaultSize = config.UI.DefaultThumbSize || 'medium';
        setThumbSize(defaultSize);
    } catch (err) {
        console.error('Fehler beim Laden der Thumbnail-Größe:', err);
        setThumbSize('medium');
    }
}

async function triggerFolderThumbnailJob(card) {
    const folderPath = card.dataset.path;
    
    try {
        const response = await fetch('/tools/folder/open', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ folderPath: folderPath })
        });
        
        const result = await response.json();
        
        if (result.success) {
            console.log('Thumbnail-Job gestartet für:', folderPath);
        }
    } catch (err) {
        console.error('Fehler beim Starten des Thumbnail-Jobs:', err);
    }
}

initThumbSize();

// Lightbox Viewer
var lightboxImages = [];
var currentLightboxIndex = 0;

function openLightbox(imagePath, allImages) {
    // Filter nur Bilder (keine Videos)
    var config = null;
    fetch('/settings/get')
        .then(function(response) { return response.json(); })
        .then(function(cfg) {
            config = cfg;
            var imageExtensions = config.Media.ImageExtensions.map(function(ext) { 
                return ext.toLowerCase(); 
            });
            
            lightboxImages = allImages.filter(function(file) {
                var ext = file.substring(file.lastIndexOf('.')).toLowerCase();
                return imageExtensions.includes(ext);
            });
            
            currentLightboxIndex = lightboxImages.indexOf(imagePath);
            
            if (currentLightboxIndex === -1) {
                console.error('Bild nicht in Liste gefunden:', imagePath);
                return;
            }
            
            showLightboxImage();
            document.getElementById('lightbox').classList.add('show');
            document.body.style.overflow = 'hidden';
        })
        .catch(function(err) {
            console.error('Fehler beim Laden der Config:', err);
        });
}

function closeLightbox() {
    document.getElementById('lightbox').classList.remove('show');
    document.body.style.overflow = '';
    
    var img = document.getElementById('lightboxImage');
    img.src = '';
    img.classList.remove('loaded');
}

function navigateLightbox(direction) {
    currentLightboxIndex += direction;
    
    if (currentLightboxIndex < 0) {
        currentLightboxIndex = lightboxImages.length - 1;
    } else if (currentLightboxIndex >= lightboxImages.length) {
        currentLightboxIndex = 0;
    }
    
    showLightboxImage();
}

function showLightboxImage() {
    var imagePath = lightboxImages[currentLightboxIndex];
    var img = document.getElementById('lightboxImage');
    var loading = document.querySelector('.lightbox-loading');
    var error = document.querySelector('.lightbox-error');
    var filename = document.getElementById('lightboxFilename');
    var counter = document.getElementById('lightboxCounter');
    
    // Reset states
    img.classList.remove('loaded');
    img.src = '';
    loading.classList.add('show');
    error.classList.remove('show');
    
    // Update info
    var name = imagePath.split('/').pop();
    filename.textContent = name;
    counter.textContent = (currentLightboxIndex + 1) + ' / ' + lightboxImages.length;
    
    // Load original image
    var originalUrl = '/original?path=' + encodeURIComponent(imagePath);
    
    var tempImg = new Image();
    tempImg.onload = function() {
        img.src = originalUrl;
        img.classList.add('loaded');
        loading.classList.remove('show');
    };
    tempImg.onerror = function() {
        loading.classList.remove('show');
        error.classList.add('show');
    };
    tempImg.src = originalUrl;
}

// Keyboard Navigation
document.addEventListener('keydown', function(e) {
    var lightbox = document.getElementById('lightbox');
    if (!lightbox.classList.contains('show')) return;
    
    if (e.key === 'Escape') {
        closeLightbox();
    } else if (e.key === 'ArrowLeft') {
        navigateLightbox(-1);
    } else if (e.key === 'ArrowRight') {
        navigateLightbox(1);
    }
});

// Click-Handler für Media-Items (wird dynamisch hinzugefügt)
function attachLightboxHandlers() {
    document.querySelectorAll('.media-item').forEach(function(item) {
        var img = item.querySelector('img');
        var checkbox = item.querySelector('.media-checkbox');
        
        if (img && !img.dataset.lightboxAttached) {
            img.dataset.lightboxAttached = 'true';
            img.style.cursor = 'pointer';
            
            img.addEventListener('click', function(e) {
                e.stopPropagation();
                
                // Nur bei Bildern, nicht bei Videos
                var filepath = item.dataset.filepath;
                var isVideo = /\.(mp4|mov|avi|mkv|webm|m4v|wmv|flv|mpg|mpeg|3gp)$/i.test(filepath);
                
                if (isVideo) return;
                
                // Sammle alle Bilder aus dem gleichen Ordner
                var folderCard = item.closest('.folder-card');
                var allMediaItems = folderCard.querySelectorAll('.media-item');
                var allFiles = Array.from(allMediaItems).map(function(mediaItem) {
                    return mediaItem.dataset.filepath;
                });
                
                openLightbox(filepath, allFiles);
            });
        }
    });
}

// Observer für dynamisch hinzugefügte Media-Items
var lightboxObserver = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
        if (mutation.addedNodes.length) {
            attachLightboxHandlers();
        }
    });
});

lightboxObserver.observe(document.body, {
    childList: true,
    subtree: true
});

// Initial attachment
document.addEventListener('DOMContentLoaded', function() {
    attachLightboxHandlers();
});
