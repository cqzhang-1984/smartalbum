"""
照片服务单元测试
"""
import pytest
from app.services.photo_service import PhotoService
from app.schemas.photo import PhotoCreate


class TestPhotoService:
    """测试照片服务"""
    
    @pytest.mark.asyncio
    async def test_create_photo(self, test_db, sample_photo_data):
        """测试创建照片记录"""
        # 创建照片数据
        photo_create = PhotoCreate(**sample_photo_data)
        
        # 创建照片
        photo = await PhotoService.create_photo(test_db, photo_create)
        
        # 验证
        assert photo is not None
        assert photo.filename == sample_photo_data["filename"]
        assert photo.file_hash == sample_photo_data["file_hash"]
        assert photo.id is not None
    
    @pytest.mark.asyncio
    async def test_get_photo_by_id(self, test_db, sample_photo_data):
        """测试根据ID获取照片"""
        # 先创建照片
        photo_create = PhotoCreate(**sample_photo_data)
        created = await PhotoService.create_photo(test_db, photo_create)
        
        # 查询照片
        photo = await PhotoService.get_photo_by_id(test_db, created.id)
        
        # 验证
        assert photo is not None
        assert photo.id == created.id
        assert photo.filename == sample_photo_data["filename"]
    
    @pytest.mark.asyncio
    async def test_get_photo_by_id_not_found(self, test_db):
        """测试获取不存在的照片"""
        photo = await PhotoService.get_photo_by_id(test_db, "non-existent-id")
        assert photo is None
    
    @pytest.mark.asyncio
    async def test_get_photo_by_hash(self, test_db, sample_photo_data):
        """测试根据哈希获取照片"""
        # 创建照片
        photo_create = PhotoCreate(**sample_photo_data)
        await PhotoService.create_photo(test_db, photo_create)
        
        # 通过哈希查询
        photo = await PhotoService.get_photo_by_hash(
            test_db, 
            sample_photo_data["file_hash"]
        )
        
        # 验证
        assert photo is not None
        assert photo.file_hash == sample_photo_data["file_hash"]
    
    @pytest.mark.asyncio
    async def test_toggle_favorite(self, test_db, sample_photo_data):
        """测试切换收藏状态"""
        # 创建照片
        photo_create = PhotoCreate(**sample_photo_data)
        photo = await PhotoService.create_photo(test_db, photo_create)
        
        # 初始状态
        initial_status = photo.is_favorite
        
        # 切换收藏
        updated = await PhotoService.toggle_favorite(test_db, photo.id)
        
        # 验证状态已切换
        assert updated is not None
        assert updated.is_favorite != initial_status
        
        # 再次切换
        updated2 = await PhotoService.toggle_favorite(test_db, photo.id)
        assert updated2.is_favorite == initial_status
    
    @pytest.mark.asyncio
    async def test_delete_photo(self, test_db, sample_photo_data):
        """测试删除照片"""
        # 创建照片
        photo_create = PhotoCreate(**sample_photo_data)
        photo = await PhotoService.create_photo(test_db, photo_create)
        photo_id = photo.id
        
        # 删除照片
        result = await PhotoService.delete_photo(test_db, photo_id)
        
        # 验证删除成功
        assert result is True
        
        # 验证已删除
        deleted = await PhotoService.get_photo_by_id(test_db, photo_id)
        assert deleted is None
    
    @pytest.mark.asyncio
    async def test_delete_photo_not_found(self, test_db):
        """测试删除不存在的照片"""
        result = await PhotoService.delete_photo(test_db, "non-existent-id")
        assert result is False
