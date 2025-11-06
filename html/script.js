let contracts = [];

let activeContract = null;
let selectedContract = null;
let invitedFriends = [];
let missionTimer = null;
let timeRemaining = 0;

$(document).ready(function() { initializeContracts(); setupEventListeners(); });

function initializeContracts() {
    const contractsContainer = $('.contracts-container');
    if (!contractsContainer.length) return;
    contractsContainer.empty();
    contracts.forEach(contract => { if (contract.available) { const contractCard = createContractCard(contract); contractsContainer.append(contractCard); } });
}

function createContractCard(contract) {
    const card = $('<div>').addClass('contract-card').attr('data-contract-id', contract.id);
    const buttonText = activeContract && activeContract.id === contract.id ? 'Active Contract' : 'Accept Contract';
    const levelSection = contract.requiredLevel ? `<div class="contract-level"><i class="vintage-icon vintage-shield"></i><span>Level ${contract.requiredLevel}+</span></div>` : '';
    card.html(`<div class="contract-header"><h3 class="contract-name">${contract.name}</h3><span class="contract-xp"><i class="vintage-icon vintage-star"></i>${contract.xp} XP</span></div><div class="contract-route"><span class="route-from">${contract.from}</span><i class="vintage-icon vintage-arrow-right"></i><span class="route-to">${contract.to}</span></div><div class="contract-details"><div class="contract-reward"><i class="vintage-icon vintage-dollar"></i><span>$${contract.reward}</span></div><div class="contract-distance"><i class="vintage-icon vintage-route"></i><span>${contract.distance} miles</span></div><div class="contract-time"><i class="vintage-icon vintage-clock"></i><span>${contract.timeLimit} min</span></div>${levelSection}</div><div class="contract-actions"><button class="accept-contract-btn" data-contract-id="${contract.id}">${buttonText}</button><div class="accept-options" style="display: none;"><button class="accept-option-btn invite-friend-btn" data-contract-id="${contract.id}"><i class="vintage-icon vintage-users"></i>Invite Friend</button><button class="accept-option-btn do-alone-btn" data-contract-id="${contract.id}"><i class="vintage-icon vintage-user"></i>Do Alone</button></div></div>`);
    return card[0];
}

function setupEventListeners() {
    $(document).on('keydown', function(e) { if (e.key === 'Escape' || e.keyCode === 27) closeUI(); });
    $(document).on('click', '.nav-btn', function() { switchSection($(this).data('section')); });
    $(document).on('click', '.accept-contract-btn', function() { showAcceptOptions(parseInt($(this).data('contract-id'))); });
    $(document).on('click', '.invite-friend-btn', function() { showMissionSetup(parseInt($(this).data('contract-id')), 'friend'); });
    $(document).on('click', '.do-alone-btn', function() { showMissionSetup(parseInt($(this).data('contract-id')), 'alone'); });
    $(document).on('click', '#add-friend-btn', function() { addFriend(); });
    $(document).on('click', '#cancel-mission-btn', function() { cancelMissionSetup(); });
    $(document).on('click', '#start-mission-btn', function() { startMission(); });
    $(document).on('click', '.remove-friend-btn', function() { removeFriend($(this).data('friend-id')); });
    $(document).on('click', '#modal-close-btn', function() { closeMissionSetup(); });
    $(document).on('click', '#mission-setup-section', function(e) { if (e.target === this) closeMissionSetup(); });
    $(document).on('click', '#cancel-active-mission-btn', function() { cancelActiveMission(); });
    $(document).on('mouseenter', '.contract-card', function() { addHoverEffects(this); });
    $(document).on('mouseleave', '.contract-card', function() { removeHoverEffects(this); });
    $(document).on('click', '.notification-close', function() { closeNotification(this); });
}

function closeUI() { $.post(`https://${GetParentResourceName()}/closeUI`, JSON.stringify({}), function(data) {}); $('.container').hide(); }

function switchSection(section) {
    $('.nav-btn').removeClass('active');
    $(`[data-section="${section}"]`).addClass('active');
    const contractsSection = $('#contracts-section'), profileSection = $('#profile-section'), activeMissionSection = $('#active-mission-section');
    if (section === 'dashboard') { contractsSection.show(); profileSection.hide(); activeMissionSection.hide(); }
    else if (section === 'profile') { contractsSection.hide(); profileSection.show(); activeMissionSection.hide(); }
    else if (section === 'active-mission') { contractsSection.hide(); profileSection.hide(); activeMissionSection.show(); updateActiveMissionDisplay(); }
}

function showAcceptOptions(contractId) { $('.accept-options').hide(); const contractCard = $(`[data-contract-id="${contractId}"]`); contractCard.find('.accept-options').show(); }

function showMissionSetup(contractId, mode = 'alone') {
    const contract = contracts.find(c => c.id === contractId);
    if (!contract || !contract.available) return;
    selectedContract = contract;
    $('#setup-mission-name').text(contract.name); $('#setup-route-from').text(contract.from); $('#setup-route-to').text(contract.to); $('#setup-reward').text(`$${contract.reward}`); $('#setup-distance').text(`${contract.distance} miles`); $('#setup-xp').text(`${contract.xp} XP`);
    invitedFriends = []; updateFriendsDisplay();
    const friendInvitation = $('.friend-invitation');
    if (mode === 'alone') friendInvitation.hide(); else friendInvitation.show();
    $('#mission-setup-section').addClass('show'); $('body').css('overflow', 'hidden');
}

function addFriend() {
    const friendIdInput = $('#friend-id-input'), friendId = friendIdInput.val().trim();
    if (!friendId) { showNotification('Please enter a friend ID', 'error'); return; }
    if (!/^\d+$/.test(friendId)) { showNotification('Please enter a valid numeric ID', 'error'); return; }
    if (invitedFriends.length >= 4) { showNotification('Maximum 4 friends allowed', 'error'); return; }
    const existingFriend = invitedFriends.find(friend => friend.id === friendId);
    if (existingFriend) { showNotification('Friend already invited', 'error'); return; }
    showNotification('Looking up player...', 'info');
    $.post(`https://${GetParentResourceName()}/getPlayerInfo`, JSON.stringify({ playerId: friendId }), function(data) {
        if (data.success) { const friendData = { id: friendId, name: data.name, source: data.source }; invitedFriends.push(friendData); friendIdInput.val(''); updateFriendsDisplay(); showNotification(`Friend ${data.name} (${friendId}) added!`, 'success'); }
        else { showNotification(data.message || 'Player not found', 'error'); }
    }).fail(function() { showNotification('Failed to lookup player', 'error'); });
}

function removeFriend(friendId) { const index = invitedFriends.findIndex(friend => friend.id === friendId); if (index > -1) { const friendName = invitedFriends[index].name; invitedFriends.splice(index, 1); updateFriendsDisplay(); showNotification(`Friend ${friendName} removed`, 'info'); } }

function updateFriendsDisplay() {
    const friendsContainer = $('#friends-container'), friendCount = $('.friend-count');
    friendsContainer.empty(); friendCount.text(`${invitedFriends.length}/4`);
    invitedFriends.forEach(friend => {
        const friendCard = $('<div>').addClass('friend-card');
        friendCard.html(`<div class="friend-info"><i class="vintage-icon vintage-user"></i><span class="friend-name">${friend.name}</span><span class="friend-id">(${friend.id})</span></div><button class="remove-friend-btn" data-friend-id="${friend.id}"><i class="vintage-icon vintage-times"></i></button>`);
        friendsContainer.append(friendCard);
    });
}

function cancelMissionSetup() { closeMissionSetup(); }
function closeMissionSetup() { $('#mission-setup-section').removeClass('show'); $('body').css('overflow', ''); selectedContract = null; invitedFriends = []; }

function startMission() {
    if (!selectedContract) return;
    activeContract = selectedContract; selectedContract.available = false;
    startMissionTimer(selectedContract.timeLimit); updateContractButtons(); showActiveMissionButton();
    activeContract.friends = invitedFriends; sendMissionStart(selectedContract, invitedFriends);
    const friendText = invitedFriends.length > 0 ? ` with ${invitedFriends.length} friend(s)` : ' alone';
    showNotification(`Mission "${selectedContract.name}" started${friendText}!`, 'success');
    closeMissionSetup(); switchSection('active-mission');
}

function sendMissionStart(contract, friends) {
    $.post(`https://${GetParentResourceName()}/startMission`, JSON.stringify({ contractId: contract.id, contractName: contract.name, from: contract.from, to: contract.to, reward: contract.reward, xp: contract.xp, distance: contract.distance, timeLimit: contract.timeLimit, friends: friends }), function(data) { if (data.success && data.groupId) showNotification(`Group created with ID: ${data.groupId}`, 'success'); }).fail(function(error) { console.error('Error sending mission data:', error); });
}

function sendMissionCompletion(contract, success = true) {
    $.post(`https://${GetParentResourceName()}/${success ? 'completeMission' : 'failMission'}`, JSON.stringify({ contractId: contract.id, contractName: contract.name, from: contract.from, to: contract.to, reward: contract.reward, xp: contract.xp, distance: contract.distance, timeLimit: contract.timeLimit, groupId: contract.groupId }), function(data) { if (data.success && data.groupCleaned) showNotification('Group cleaned up successfully', 'info'); }).fail(function(error) { console.error('Error sending mission completion data:', error); });
}

function cancelActiveContract() {
    if (!activeContract) return;
    const contract = contracts.find(c => c.id === activeContract.id);
    if (contract) contract.available = true;
    stopMissionTimer(); activeContract = null; updateContractButtons(); hideActiveMissionButton(); showNotification('Active contract cancelled.', 'info');
}

function showActiveMissionButton() { const activeMissionBtn = $('.active-mission-btn'); if (activeMissionBtn.length) activeMissionBtn.show(); }
function hideActiveMissionButton() { const activeMissionBtn = $('.active-mission-btn'); if (activeMissionBtn.length) activeMissionBtn.hide(); }

function startMissionTimer(timeLimitMinutes) {
    if (missionTimer) clearInterval(missionTimer);
    timeRemaining = timeLimitMinutes * 60;
    missionTimer = setInterval(() => { timeRemaining--; updateTimerDisplay(); if (timeRemaining <= 0) handleMissionTimeout(); }, 1000);
    updateTimerDisplay();
}

function stopMissionTimer() { if (missionTimer) { clearInterval(missionTimer); missionTimer = null; } timeRemaining = 0; }

function updateTimerDisplay() {
    const timerElement = $('#mission-timer');
    if (!timerElement.length) return;
    const minutes = Math.floor(timeRemaining / 60), seconds = timeRemaining % 60;
    const timeString = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    timerElement.text(timeString);
    if (timeRemaining <= 300) timerElement.addClass('timer-warning'); else timerElement.removeClass('timer-warning');
    if (timeRemaining <= 60) timerElement.addClass('timer-critical'); else timerElement.removeClass('timer-critical');
}

function handleMissionTimeout() {
    stopMissionTimer();
    if (activeContract) {
        showNotification(`Mission "${activeContract.name}" has timed out!`, 'error');
        sendMissionCompletion(activeContract, false);
        const contract = contracts.find(c => c.id === activeContract.id);
        if (contract) contract.available = true;
        activeContract = null; updateContractButtons(); hideActiveMissionButton(); switchSection('dashboard');
    }
}

function updateActiveMissionDisplay() {
    if (!activeContract) return;
    $('#active-mission-name').text(activeContract.name); $('#active-route-from').text(activeContract.from); $('#active-route-to').text(activeContract.to); $('#active-reward').text(`$${activeContract.reward}`); $('#active-distance').text(`${activeContract.distance} miles`); $('#active-xp').text(`${activeContract.xp} XP`);
    updateMissionProgress(0); updateTimerDisplay();
}

function updateMissionProgress(percentage) { const progressFill = $('#mission-progress-fill'), progressText = $('#mission-progress-text'); if (progressFill.length && progressText.length) { progressFill.css('width', `${percentage}%`); progressText.text(`${percentage}% Complete`); } }

function cancelActiveMission() { if (!activeContract) return; sendMissionCompletion(activeContract, false); cancelActiveContract(); switchSection('dashboard'); showNotification('Mission cancelled successfully.', 'info'); }

function updateContractButtons() {
    $('.accept-contract-btn').each(function() {
        const button = $(this), contractId = parseInt(button.data('contract-id')), contract = contracts.find(c => c.id === contractId);
        if (activeContract && activeContract.id === contractId) { button.text('Active Contract'); button.prop('disabled', true); }
        else if (!contract.available) { button.text('Unavailable'); button.prop('disabled', true); }
        else { button.text('Accept Contract'); button.prop('disabled', false); }
    });
}

function addHoverEffects(card) { $(card).css({ 'border-color': 'rgba(255, 208, 142, 0.6)', 'box-shadow': '0 10px 30px rgba(255, 208, 142, 0.2)' }); }
function removeHoverEffects(card) { $(card).css({ 'border-color': '', 'box-shadow': '' }); }

function sendContractAccepted(contract, mode = 'alone') { $.post(`https://${GetParentResourceName()}/acceptContract`, JSON.stringify({ contractId: contract.id, contractName: contract.name, from: contract.from, to: contract.to, reward: contract.reward, distance: contract.distance, difficulty: contract.difficulty, mode: mode }), function(data) {}).fail(function(error) { console.error('Error sending contract data:', error); }); }

function showNotification(message, type = 'info') {
    const notification = $(`<div class="notification notification-${type}">`);
    let icon = 'vintage-icon vintage-info';
    switch (type) { case 'success': icon = 'vintage-icon vintage-check'; break; case 'error': icon = 'vintage-icon vintage-exclamation'; break; case 'info': default: icon = 'vintage-icon vintage-info'; break; }
    notification.html(`<div class="notification-content"><i class="notification-icon ${icon}"></i><div class="notification-text">${message}</div></div><button class="notification-close"><i class="vintage-icon vintage-times"></i></button>`);
    $('body').append(notification);
    setTimeout(() => notification.addClass('show'), 100);
    setTimeout(() => closeNotification(notification.find('.notification-close')), 4000);
}

function closeNotification(closeButton) { const notification = $(closeButton).closest('.notification'); if (notification.length) { notification.removeClass('show'); setTimeout(() => notification.remove(), 400); } }

function updatePlayerData(playerData) {
    if (playerData.name) $('.my-name').text(playerData.name);
    if (playerData.level) { $('.level-display').text(`LVL ${playerData.level}`); $('.level-number').text(playerData.level); }
    if (playerData.xp !== undefined && playerData.maxXp !== undefined) { const xpPercentage = (playerData.xp / playerData.maxXp) * 100; $('.progress-fill').css('width', `${xpPercentage}%`); $('.current-xp').text(`${playerData.xp.toLocaleString()} XP`); $('.next-level').text(`Next: ${playerData.maxXp.toLocaleString()} XP`); }
    if (playerData.totalDeliveries !== undefined) $('.stat-item').eq(0).find('.stat-number').text(playerData.totalDeliveries);
    if (playerData.totalEarnings !== undefined) $('.stat-item').eq(1).find('.stat-number').text(`$${playerData.totalEarnings.toLocaleString()}`);
    if (playerData.successRate !== undefined) $('.stat-item').eq(2).find('.stat-number').text(`${playerData.successRate}%`);
    if (playerData.daysActive !== undefined) $('.stat-item').eq(3).find('.stat-number').text(playerData.daysActive);
    if (playerData.recentDeliveries && playerData.recentDeliveries.length > 0) updateRecentDeliveries(playerData.recentDeliveries);
}

function updateRecentDeliveries(deliveries) {
    const deliveriesList = $('.deliveries-list');
    deliveriesList.empty();
    if (!deliveries || deliveries.length === 0) { deliveriesList.append(`<div class="delivery-item no-deliveries"><div class="delivery-route"><span>No recent deliveries</span></div><div class="delivery-details"><span class="delivery-time">Start your first mission!</span></div></div>`); return; }
    deliveries.slice(0, 3).forEach(delivery => {
        const status = delivery.status || 'completed', statusClass = status === 'failed' ? 'failed' : 'completed', rewardText = status === 'failed' ? '-$0' : `+$${delivery.reward}`, statusIcon = status === 'failed' ? 'vintage-times' : 'vintage-check';
        const deliveryItem = $(`<div class="delivery-item ${statusClass}"><div class="delivery-route"><span class="from">${delivery.from}</span><i class="vintage-icon vintage-arrow-right"></i><span class="to">${delivery.to}</span></div><div class="delivery-details"><span class="delivery-reward ${status}">${rewardText}</span><span class="delivery-time">${formatDeliveryTime(delivery.time)}</span><i class="vintage-icon ${statusIcon} delivery-status-icon"></i></div></div>`);
        deliveriesList.append(deliveryItem);
    });
}

function formatDeliveryTime(timeString) { const deliveryTime = new Date(timeString), now = new Date(), diffMs = now - deliveryTime, diffHours = Math.floor(diffMs / (1000 * 60 * 60)), diffDays = Math.floor(diffHours / 24); if (diffDays > 0) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`; else if (diffHours > 0) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`; else return 'Just now'; }

$(window).on("message", function (e) {
    e = e.originalEvent.data;
    switch (e.action) {
        case "openDeliveryUi": $('.container').show(); if (e.data) updatePlayerData(e.data); if (e.contracts) { contracts = e.contracts; initializeContracts(); } break;
        case "updateStatusBar": $('.status-bar').show(); $('.status-bar-text').text(e.text); break;
        case "hideStatusBar": $('.status-bar').hide(); break;
        case "closeDeliveryUi": $('.container').hide(); break;
        case "updateContracts": if (e.contracts) { contracts = e.contracts; initializeContracts(); } break;
        case "updateMissionProgress": if (e.progress !== undefined) updateMissionProgress(e.progress); break;
        case "completeMissionCallback": if (activeContract && e.data && e.data.contractId === activeContract.id) { stopMissionTimer(); showNotification(`Contract "${activeContract.name}" completed! Reward: $${activeContract.reward} + ${activeContract.xp} XP`, 'success'); const contract = contracts.find(c => c.id === activeContract.id); if (contract) contract.available = true; activeContract = null; updateContractButtons(); hideActiveMissionButton(); switchSection('dashboard'); if (e.playerData) updatePlayerData(e.playerData); else $.post(`https://${GetParentResourceName()}/getPlayerData`, JSON.stringify({}), function(data) { if (data) updatePlayerData(data); }); } break;
        case "missionCompleted": if (activeContract && e.contractId === activeContract.id) { stopMissionTimer(); showNotification(`Mission "${activeContract.name}" completed! Reward: $${activeContract.reward} + ${activeContract.xp} XP`, 'success'); const contract = contracts.find(c => c.id === activeContract.id); if (contract) contract.available = true; activeContract = null; updateContractButtons(); hideActiveMissionButton(); switchSection('dashboard'); if (e.playerData) updatePlayerData(e.playerData); else $.post(`https://${GetParentResourceName()}/getPlayerData`, JSON.stringify({}), function(data) { if (data) updatePlayerData(data); }); } break;
        default: return;
    }
});
