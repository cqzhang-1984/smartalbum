"""
向量数据库服务 - 使用 ChromaDB 持久化存储（支持降级到 JSON 文件）
"""
import numpy as np
from typing import List, Dict, Optional
from app.config import settings
import os
import json
import asyncio
from concurrent.futures import ThreadPoolExecutor

try:
    import chromadb
    from chromadb.config import Settings as ChromaSettings
    CHROMADB_AVAILABLE = True
except ImportError:
    CHROMADB_AVAILABLE = False

try:
    from app.services.ai_service import embedding_service
except ImportError:
    embedding_service = None

try:
    from app.services.logger_service import logger_service
except ImportError:
    # 降级：如果 logger_service 不可用，使用简单的 print 包装
    class SimpleLogger:
        @staticmethod
        def info(msg): print(f"[INFO] {msg}")
        @staticmethod
        def warning(msg): print(f"[WARN] {msg}")
        @staticmethod
        def error(msg): print(f"[ERROR] {msg}")
        @staticmethod
        def debug(msg): print(f"[DEBUG] {msg}")
    logger_service = SimpleLogger()


class VectorService:
    """向量数据库服务类 - 优先使用 ChromaDB，降级使用 JSON 文件"""
    
    def __init__(self):
        self.client = None
        self.collection = None
        self._executor = ThreadPoolExecutor(max_workers=4)
        self._initialized = False
        self._use_chroma = False
        
        # 降级方案：JSON 文件存储
        self.vectors: Dict[str, Dict] = {}
        self.storage_path = os.path.join(
            settings.DATABASE_PATH.replace('smartalbum.db', ''), 
            'vectors.json'
        )
        
        # 尝试初始化 ChromaDB
        if CHROMADB_AVAILABLE:
            try:
                self._init_chroma()
                self._use_chroma = True
            except Exception as e:
                print(f"[WARN] ChromaDB initialization failed: {e}, using JSON fallback")
                self._init_json_fallback()
        else:
            self._init_json_fallback()
    
    def _init_json_fallback(self):
        """初始化 JSON 文件存储（降级方案）"""
        self._ensure_storage_dir()
        self._load_from_disk()
        self._initialized = True
        print(f"[INFO] VectorService initialized with JSON storage: {len(self.vectors)} vectors")
    
    def _ensure_storage_dir(self):
        """确保存储目录存在"""
        storage_dir = os.path.dirname(self.storage_path)
        if storage_dir and not os.path.exists(storage_dir):
            os.makedirs(storage_dir, exist_ok=True)
    
    def _load_from_disk(self):
        """从磁盘加载向量数据"""
        try:
            if os.path.exists(self.storage_path):
                with open(self.storage_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    self.vectors = data.get('vectors', {})
        except Exception as e:
            logger_service.warning(f"Failed to load vectors from disk: {e}")
            self.vectors = {}
    
    def _save_to_disk(self):
        """保存向量数据到磁盘"""
        try:
            with open(self.storage_path, 'w', encoding='utf-8') as f:
                json.dump({
                    'vectors': self.vectors,
                    'version': '1.0'
                }, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"[ERROR] Failed to save vectors to disk: {e}")
    
    def _init_chroma(self):
        """初始化 ChromaDB 客户端"""
        # 确保存储目录存在
        chroma_path = settings.CHROMA_PATH
        os.makedirs(chroma_path, exist_ok=True)
        
        # 创建 ChromaDB 客户端
        self.client = chromadb.PersistentClient(
            path=chroma_path,
            settings=ChromaSettings(
                anonymized_telemetry=False,
                allow_reset=True
            )
        )
        
        # 获取或创建集合
        self.collection = self.client.get_or_create_collection(
            name="photos",
            metadata={"hnsw:space": "cosine"}  # 使用余弦距离
        )
        
        self._initialized = True
        count = self.collection.count()
        print(f"[INFO] VectorService initialized with ChromaDB: {chroma_path}, vectors: {count}")
    
    async def add_photo_embedding(
        self,
        photo_id: str,
        description: str,
        metadata: Optional[Dict] = None
    ) -> bool:
        """
        添加照片向量到数据库
        
        Args:
            photo_id: 照片ID
            description: 照片描述文本
            metadata: 额外元数据（如标签等）
            
        Returns:
            是否成功
        """
        if not self._initialized or embedding_service is None:
            return False
        
        try:
            # 生成向量
            embedding = await embedding_service.generate_embedding(description)
            
            if not embedding:
                return False
            
            if self._use_chroma:
                # 在后台线程中执行 ChromaDB 操作
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(
                    self._executor,
                    self._sync_add_embedding,
                    photo_id,
                    embedding,
                    description,
                    metadata or {}
                )
            else:
                # 使用 JSON 文件存储
                self.vectors[photo_id] = {
                    'embedding': embedding,
                    'description': description,
                    'metadata': metadata or {}
                }
                self._save_to_disk()
            
            return True
            
        except Exception as e:
            print(f"添加向量失败: {e}")
            return False
    
    def _sync_add_embedding(self, photo_id: str, embedding: List[float], 
                           description: str, metadata: Dict):
        """同步添加向量到 ChromaDB"""
        self.collection.add(
            ids=[photo_id],
            embeddings=[embedding],
            documents=[description],
            metadatas=[metadata]
        )
    
    async def search_similar_photos(
        self,
        query: str,
        n_results: int = 20
    ) -> List[Dict]:
        """
        搜索相似照片
        
        Args:
            query: 搜索查询文本
            n_results: 返回结果数量
            
        Returns:
            相似照片列表
        """
        if not self._initialized or embedding_service is None:
            return []
        
        try:
            # 生成查询向量
            query_embedding = await embedding_service.generate_embedding(query)
            
            if not query_embedding:
                return []
            
            if self._use_chroma:
                # 在后台线程中执行 ChromaDB 搜索
                loop = asyncio.get_event_loop()
                return await loop.run_in_executor(
                    self._executor,
                    self._sync_search,
                    query_embedding,
                    n_results
                )
            else:
                # JSON 文件线性搜索
                return self._search_json(query_embedding, n_results)
            
        except Exception as e:
            print(f"搜索失败: {e}")
            return []
    
    def _sync_search(self, query_embedding: List[float], n_results: int) -> List[Dict]:
        """同步执行 ChromaDB 搜索"""
        try:
            results = self.collection.query(
                query_embeddings=[query_embedding],
                n_results=min(n_results, self.collection.count() or 1),
                include=["documents", "metadatas", "distances"]
            )
            
            output = []
            if results['ids'] and results['ids'][0]:
                for i, photo_id in enumerate(results['ids'][0]):
                    output.append({
                        'photo_id': photo_id,
                        'description': results['documents'][0][i] if results['documents'] else '',
                        'metadata': results['metadatas'][0][i] if results['metadatas'] else {},
                        'distance': results['distances'][0][i] if results['distances'] else 0.0
                    })
            return output
        except Exception as e:
            print(f"ChromaDB 搜索失败: {e}")
            return []
    
    def _search_json(self, query_embedding: List[float], n_results: int) -> List[Dict]:
        """JSON 文件存储的线性搜索"""
        results = []
        query_vec = np.array(query_embedding)
        
        for photo_id, data in self.vectors.items():
            if data.get('embedding') is None:
                continue
            
            vec = np.array(data['embedding'])
            similarity = np.dot(query_vec, vec) / (np.linalg.norm(query_vec) * np.linalg.norm(vec))
            distance = 1 - similarity
            
            results.append({
                'photo_id': photo_id,
                'description': data['description'],
                'metadata': data.get('metadata', {}),
                'distance': float(distance)
            })
        
        results.sort(key=lambda x: x['distance'])
        return results[:n_results]
    
    async def delete_photo_embedding(self, photo_id: str) -> bool:
        """
        删除照片向量
        
        Args:
            photo_id: 照片ID
            
        Returns:
            是否成功
        """
        if not self._initialized:
            return False
        
        try:
            if self._use_chroma:
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(
                    self._executor,
                    self._sync_delete,
                    photo_id
                )
            else:
                # JSON 文件删除
                if photo_id in self.vectors:
                    del self.vectors[photo_id]
                    self._save_to_disk()
            return True
        except Exception as e:
            print(f"删除向量失败: {e}")
            return False
    
    def _sync_delete(self, photo_id: str):
        """同步删除向量（ChromaDB）"""
        try:
            self.collection.delete(ids=[photo_id])
        except Exception:
            pass  # 可能ID不存在
    
    async def update_photo_embedding(
        self,
        photo_id: str,
        description: str,
        metadata: Optional[Dict] = None
    ) -> bool:
        """
        更新照片向量
        
        Args:
            photo_id: 照片ID
            description: 照片描述文本
            metadata: 额外元数据
            
        Returns:
            是否成功
        """
        # 删除旧向量并添加新向量
        await self.delete_photo_embedding(photo_id)
        return await self.add_photo_embedding(photo_id, description, metadata)
    
    def get_collection_stats(self) -> Dict:
        """
        获取集合统计信息
        
        Returns:
            统计信息
        """
        if not self._initialized:
            return {
                'total_vectors': 0,
                'collection_name': 'photos',
                'storage_type': 'chroma' if self._use_chroma else 'json',
                'status': 'not_initialized'
            }
        
        try:
            if self._use_chroma:
                count = self.collection.count()
                return {
                    'total_vectors': count,
                    'collection_name': 'photos',
                    'storage_type': 'chroma',
                    'storage_path': settings.CHROMA_PATH,
                    'status': 'active'
                }
            else:
                return {
                    'total_vectors': len(self.vectors),
                    'collection_name': 'photos',
                    'storage_type': 'json',
                    'storage_path': self.storage_path,
                    'status': 'active'
                }
        except Exception as e:
            return {
                'total_vectors': 0,
                'collection_name': 'photos',
                'storage_type': 'chroma' if self._use_chroma else 'json',
                'status': f'error: {str(e)}'
            }
    
    async def rebuild_index(self) -> int:
        """
        重建向量索引（从数据库同步）
        
        Returns:
            重建的向量数量
        """
        if not self._initialized:
            return 0
        
        try:
            if self._use_chroma:
                return self.collection.count()
            else:
                return len(self.vectors)
        except Exception:
            return 0
    
    async def batch_add_embeddings(
        self,
        items: List[Dict[str, any]]
    ) -> int:
        """
        批量添加向量
        
        Args:
            items: 列表项，每项包含 photo_id, description, metadata
            
        Returns:
            成功添加的数量
        """
        if not self._initialized or embedding_service is None:
            return 0
        
        if not items:
            return 0
        
        try:
            # 批量生成向量
            descriptions = [item['description'] for item in items]
            embeddings = await embedding_service.generate_embeddings_batch(descriptions)
            
            # 准备数据
            ids = []
            docs = []
            metas = []
            embs = []
            
            for i, item in enumerate(items):
                if i < len(embeddings) and embeddings[i]:
                    ids.append(item['photo_id'])
                    docs.append(item['description'])
                    metas.append(item.get('metadata', {}))
                    embs.append(embeddings[i])
            
            if not ids:
                return 0
            
            if self._use_chroma:
                # 批量添加到 ChromaDB
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(
                    self._executor,
                    self._sync_batch_add,
                    ids, embs, docs, metas
                )
            else:
                # 批量添加到 JSON
                for i, photo_id in enumerate(ids):
                    self.vectors[photo_id] = {
                        'embedding': embs[i],
                        'description': docs[i],
                        'metadata': metas[i]
                    }
                self._save_to_disk()
            
            return len(ids)
            
        except Exception as e:
            print(f"批量添加向量失败: {e}")
            return 0
    
    def _sync_batch_add(self, ids: List[str], embeddings: List[List[float]], 
                       documents: List[str], metadatas: List[Dict]):
        """同步批量添加向量到 ChromaDB"""
        self.collection.add(
            ids=ids,
            embeddings=embeddings,
            documents=documents,
            metadatas=metadatas
        )


# 创建全局实例
vector_service = VectorService()
