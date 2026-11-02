
const DB_NAME = 'PodcastUltraOffline';
const DB_VERSION = 1;
const STORE_NAME = 'episodes';

const openDB = (): Promise<IDBDatabase> => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
};

export const saveOfflineEpisode = async (trackId: number, blob: Blob): Promise<void> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.put(blob, trackId.toString());
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
};

export const getOfflineEpisode = async (trackId: number): Promise<Blob | null> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.get(trackId.toString());
    request.onsuccess = () => resolve(request.result || null);
    request.onerror = () => reject(request.error);
  });
};

export const deleteOfflineEpisode = async (trackId: number): Promise<void> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.delete(trackId.toString());
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
};

export const getAllOfflineIds = async (): Promise<number[]> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.getAllKeys();
    request.onsuccess = () => resolve((request.result as string[]).map(Number));
    request.onerror = () => reject(request.error);
  });
};

export const getAllOfflineEpisodes = async (): Promise<{ id: number; size: number }[]> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const keysReq = store.getAllKeys();
    const blobsReq = store.getAll();
    let keys: IDBValidKey[] = [];
    let blobs: Blob[] = [];
    keysReq.onsuccess = () => { keys = keysReq.result; };
    blobsReq.onsuccess = () => {
      blobs = blobsReq.result as Blob[];
      resolve(keys.map((k, i) => ({ id: Number(k), size: blobs[i]?.size || 0 })));
    };
    blobsReq.onerror = () => reject(blobsReq.error);
  });
};

export const getOfflineStorageStats = async (): Promise<{ totalBytes: number; count: number }> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.getAll();
    request.onsuccess = () => {
      const blobs = request.result as Blob[];
      const totalBytes = blobs.reduce((acc, blob) => acc + blob.size, 0);
      resolve({ totalBytes, count: blobs.length });
    };
    request.onerror = () => reject(request.error); // Safe fallback
  });
};

export const clearAllOfflineEpisodes = async (): Promise<void> => {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.clear();
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
};
