"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBranchStatistics = exports.calculateDailyBranchStatistics = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const axios_1 = __importDefault(require("axios"));
admin.initializeApp();
const db = admin.firestore();
// Fetch daily branch statistics
exports.calculateDailyBranchStatistics = (0, scheduler_1.onSchedule)('every 24 hours', async (event) => {
    try {
        const url = 'https://api.github.com/repos/mboetger/flutter/git/matching-refs/heads/triage-issue-';
        const response = await axios_1.default.get(url);
        const data = response.data;
        const fileStats = {};
        let totalBranchesAnalyzed = 0;
        for (const item of data) {
            const ref = item.ref;
            if (ref && ref.startsWith('refs/heads/')) {
                const branchName = ref.substring('refs/heads/'.length);
                try {
                    // Compare with base master
                    let baseSha = '';
                    const compareUrl = `https://api.github.com/repos/flutter/flutter/compare/master...mboetger:${branchName}`;
                    try {
                        const compareRes = await axios_1.default.get(compareUrl);
                        baseSha = compareRes.data.merge_base_commit.sha;
                    }
                    catch (e) {
                        const compareUrlFallback = `https://api.github.com/repos/mboetger/flutter/compare/flutter:master...${branchName}`;
                        const compareResFallback = await axios_1.default.get(compareUrlFallback);
                        baseSha = compareResFallback.data.merge_base_commit.sha;
                    }
                    if (baseSha) {
                        const finalCompareUrl = `https://api.github.com/repos/mboetger/flutter/compare/${baseSha}...${branchName}`;
                        const diffRes = await axios_1.default.get(finalCompareUrl);
                        const files = diffRes.data.files;
                        if (files && Array.isArray(files)) {
                            for (const file of files) {
                                const filename = file.filename;
                                const changes = file.changes;
                                if (!fileStats[filename]) {
                                    fileStats[filename] = { changes: 0, branches: 0 };
                                }
                                fileStats[filename].changes += changes;
                                fileStats[filename].branches += 1;
                            }
                        }
                        totalBranchesAnalyzed++;
                    }
                }
                catch (e) {
                    console.error(`Error processing branch ${branchName}:`, e);
                }
            }
        }
        const sortedFiles = Object.entries(fileStats)
            .sort((a, b) => b[1].changes - a[1].changes)
            .slice(0, 50); // top 50 files
        await db.collection('statistics').doc('daily').set({
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            totalBranchesAnalyzed,
            topFiles: sortedFiles.map(([filename, stats]) => ({
                filename,
                changes: stats.changes,
                branches: stats.branches
            }))
        });
        console.log('Daily statistics calculated and saved.');
    }
    catch (error) {
        console.error('Error calculating statistics:', error);
    }
});
exports.getBranchStatistics = (0, https_1.onRequest)({ cors: true }, async (req, res) => {
    try {
        const doc = await db.collection('statistics').doc('daily').get();
        if (!doc.exists) {
            res.status(404).json({ error: 'Statistics not found' });
            return;
        }
        res.json(doc.data());
    }
    catch (error) {
        console.error('Error fetching statistics:', error);
        res.status(500).json({ error: 'Internal Server Error' });
    }
});
//# sourceMappingURL=index.js.map