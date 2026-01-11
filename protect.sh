#!/bin/bash

# Script Auto Protection Panel Pterodactyl
# Created by ZarOffc
# Support: t.me/ZarOffc

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Base directory
BASE_DIR="/var/www/pterodactyl"
WATERMARK="⛔ Access Blocked by Anti-Rusuh - © Protect by ZarSystem (v1.1)"

# Function to show header
show_header() {
    clear
    echo -e "${BLUE}"
    echo "=========================================="
    echo "🔒 PANEL PROTECTION INSTALLER"
    echo "=========================================="
    echo -e "${NC}"
}

# Function to create backup
backup_file() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        cp "$file_path" "$file_path.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${GREEN}✓ Backup created for $file_path${NC}"
    fi
}

# Function to create directory if not exists
create_dir() {
    local dir_path=$1
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path"
        echo -e "${YELLOW}📁 Created directory: $dir_path${NC}"
    fi
}

# Function to write file
write_file() {
    local file_path=$1
    local content=$2
    
    create_dir "$(dirname "$file_path")"
    backup_file "$file_path"
    
    echo "$content" > "$file_path"
    echo -e "${GREEN}✅ File updated: $file_path${NC}"
}

# Function to install protection
install_protection() {
    show_header
    echo -e "${YELLOW}🚀 Starting Protection Installation...${NC}"
    echo ""
    
    # Check if panel directory exists
    if [ ! -d "$BASE_DIR" ]; then
        echo -e "${RED}❌ Directory panel tidak ditemukan: $BASE_DIR${NC}"
        echo -e "${YELLOW}Pastikan Pterodactyl terinstall di directory yang benar.${NC}"
        exit 1
    fi

    # ==========================================
    # 1. ANTI DELETE SERVER
    # ==========================================
    SERVER_DELETION_SERVICE="<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class ServerDeletionService
{
    protected bool \$force = false;

    /**
     * ServerDeletionService constructor.
     */
    public function __construct(
        private ConnectionInterface \$connection,
        private DaemonServerRepository \$daemonServerRepository,
        private DatabaseManagementService \$databaseManagementService
    ) {
    }

    /**
     * Set if the server should be forcibly deleted from the panel (ignoring daemon errors) or not.
     */
    public function withForce(bool \$bool = true): self
    {
        \$this->force = \$bool;
        return \$this;
    }

    /**
     * Delete a server from the panel and remove any associated databases from hosts.
     *
     * @throws \Throwable
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function handle(Server \$server): void
    {
        \$user = Auth::user();

        // 🔒 Proteksi: hanya Admin ID = 1 boleh menghapus server siapa saja.
        // Selain itu, user biasa hanya boleh menghapus server MILIKNYA SENDIRI.
        // Jika tidak ada informasi pemilik dan pengguna bukan admin, tolak.
        if (\$user) {
            if (\$user->id !== 1) {
                // Coba deteksi owner dengan beberapa fallback yang umum.
                \$ownerId = \$server->owner_id
                    ?? \$server->user_id
                    ?? (\$server->owner?->id ?? null)
                    ?? (\$server->user?->id ?? null);

                if (\$ownerId === null) {
                    // Tidak jelas siapa pemiliknya — jangan izinkan pengguna biasa menghapus.
                    throw new DisplayException('Akses ditolak: informasi pemilik server tidak tersedia.');
                }

                if (\$ownerId !== \$user->id) {
                    throw new DisplayException('$WATERMARK');
                }
            }
            // jika \$user->id === 1, lanjutkan (admin super)
        }
        // Jika tidak ada \$user (mis. CLI/background job), biarkan proses berjalan.

        try {
            \$this->daemonServerRepository->setServer(\$server)->delete();
        } catch (DaemonConnectionException \$exception) {
            // Abaikan error 404, tapi lempar error lain jika tidak mode force
            if (!\$this->force && \$exception->getStatusCode() !== Response::HTTP_NOT_FOUND) {
                throw \$exception;
            }

            Log::warning(\$exception);
        }

        \$this->connection->transaction(function () use (\$server) {
            foreach (\$server->databases as \$database) {
                try {
                    \$this->databaseManagementService->delete(\$database);
                } catch (\Exception \$exception) {
                    if (!\$this->force) {
                        throw \$exception;
                    }

                    // Jika gagal delete database di host, tetap hapus dari panel
                    \$database->delete();
                    Log::warning(\$exception);
                }
            }

            \$server->delete();
        });
    }
}"
    write_file "$BASE_DIR/app/Services/Servers/ServerDeletionService.php" "$SERVER_DELETION_SERVICE"

    # ==========================================
    # 2. ANTI DELETE USER
    # ==========================================
    USER_CONTROLLER="<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Model;
use Illuminate\Support\Collection;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Spatie\QueryBuilder\QueryBuilder;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Contracts\Translation\Translator;
use Pterodactyl\Services\Users\UserUpdateService;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Users\UserCreationService;
use Pterodactyl\Services\Users\UserDeletionService;
use Pterodactyl\Http\Requests\Admin\UserFormRequest;
use Pterodactyl\Http\Requests\Admin\NewUserFormRequest;
use Pterodactyl\Contracts\Repository\UserRepositoryInterface;

class UserController extends Controller
{
    use AvailableLanguages;

    /**
     * UserController constructor.
     */
    public function __construct(
        protected AlertsMessageBag \$alert,
        protected UserCreationService \$creationService,
        protected UserDeletionService \$deletionService,
        protected Translator \$translator,
        protected UserUpdateService \$updateService,
        protected UserRepositoryInterface \$repository,
        protected ViewFactory \$view
    ) {
    }

    /**
     * Display user index page.
     */
    public function index(Request \$request): View
    {
        \$users = QueryBuilder::for(
            User::query()->select('users.*')
                ->selectRaw('COUNT(DISTINCT(subusers.id)) as subuser_of_count')
                ->selectRaw('COUNT(DISTINCT(servers.id)) as servers_count')
                ->leftJoin('subusers', 'subusers.user_id', '=', 'users.id')
                ->leftJoin('servers', 'servers.owner_id', '=', 'users.id')
                ->groupBy('users.id')
        )
            ->allowedFilters(['username', 'email', 'uuid'])
            ->allowedSorts(['id', 'uuid'])
            ->paginate(50);

        return \$this->view->make('admin.users.index', ['users' => \$users]);
    }

    /**
     * Display new user page.
     */
    public function create(): View
    {
        return \$this->view->make('admin.users.new', [
            'languages' => \$this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Display user view page.
     */
    public function view(User \$user): View
    {
        return \$this->view->make('admin.users.view', [
            'user' => \$user,
            'languages' => \$this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Delete a user from the system.
     *
     * @throws \Exception
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function delete(Request \$request, User \$user): RedirectResponse
    {
        // === FITUR TAMBAHAN: Proteksi hapus user ===
        if (\$request->user()->id !== 1) {
            throw new DisplayException(\"$WATERMARK\");
        }
        // ============================================

        if (\$request->user()->id === \$user->id) {
            throw new DisplayException(\$this->translator->get('admin/user.exceptions.user_has_servers'));
        }

        \$this->deletionService->handle(\$user);

        return redirect()->route('admin.users');
    }

    /**
     * Create a user.
     *
     * @throws \Exception
     * @throws \Throwable
     */
    public function store(NewUserFormRequest \$request): RedirectResponse
    {
        \$user = \$this->creationService->handle(\$request->normalize());
        \$this->alert->success(\$this->translator->get('admin/user.notices.account_created'))->flash();

        return redirect()->route('admin.users.view', \$user->id);
    }

    /**
     * Update a user on the system.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function update(UserFormRequest \$request, User \$user): RedirectResponse
    {
        // === FITUR TAMBAHAN: Proteksi ubah data penting ===
        \$restrictedFields = ['email', 'first_name', 'last_name', 'password'];

        foreach (\$restrictedFields as \$field) {
            if (\$request->filled(\$field) && \$request->user()->id !== 1) {
                throw new DisplayException(\"$WATERMARK\");
            }
        }

        // Cegah turunkan level admin ke user biasa
        if (\$user->root_admin && \$request->user()->id !== 1) {
            throw new DisplayException(\"$WATERMARK\");
        }
        // ====================================================

        \$this->updateService
            ->setUserLevel(User::USER_LEVEL_ADMIN)
            ->handle(\$user, \$request->normalize());

        \$this->alert->success(trans('admin/user.notices.account_updated'))->flash();

        return redirect()->route('admin.users.view', \$user->id);
    }

    /**
     * Get a JSON response of users on the system.
     */
    public function json(Request \$request): Model|Collection
    {
        \$users = QueryBuilder::for(User::query())->allowedFilters(['email'])->paginate(25);

        // Handle single user requests.
        if (\$request->query('user_id')) {
            \$user = User::query()->findOrFail(\$request->input('user_id'));
            \$user->md5 = md5(strtolower(\$user->email));

            return \$user;
        }

        return \$users->map(function (\$item) {
            \$item->md5 = md5(strtolower(\$item->email));

            return \$item;
        });
    }
}"
    write_file "$BASE_DIR/app/Http/Controllers/Admin/UserController.php" "$USER_CONTROLLER"

    # ==========================================
    # 3. ANTI INTIP LOCATION
    # ==========================================
    LOCATION_CONTROLLER="<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Location;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\LocationFormRequest;
use Pterodactyl\Services\Locations\LocationUpdateService;
use Pterodactyl\Services\Locations\LocationCreationService;
use Pterodactyl\Services\Locations\LocationDeletionService;
use Pterodactyl\Contracts\Repository\LocationRepositoryInterface;

class LocationController extends Controller
{
    /**
     * LocationController constructor.
     */
    public function __construct(
        protected AlertsMessageBag \$alert,
        protected LocationCreationService \$creationService,
        protected LocationDeletionService \$deletionService,
        protected LocationRepositoryInterface \$repository,
        protected LocationUpdateService \$updateService,
        protected ViewFactory \$view
    ) {
    }

    /**
     * Return the location overview page.
     */
    public function index(): View
    {
        // 🔒 Cegah akses selain admin ID 1
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        return \$this->view->make('admin.locations.index', [
            'locations' => \$this->repository->getAllWithDetails(),
        ]);
    }

    /**
     * Return the location view page.
     *
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function view(int \$id): View
    {
        // 🔒 Cegah akses selain admin ID 1
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        return \$this->view->make('admin.locations.view', [
            'location' => \$this->repository->getWithNodes(\$id),
        ]);
    }

    /**
     * Handle request to create new location.
     *
     * @throws \Throwable
     */
    public function create(LocationFormRequest \$request): RedirectResponse
    {
        // 🔒 Cegah akses selain admin ID 1
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        \$location = \$this->creationService->handle(\$request->normalize());
        \$this->alert->success('Location was created successfully.')->flash();

        return redirect()->route('admin.locations.view', \$location->id);
    }

    /**
     * Handle request to update or delete location.
     *
     * @throws \Throwable
     */
    public function update(LocationFormRequest \$request, Location \$location): RedirectResponse
    {
        // 🔒 Cegah akses selain admin ID 1
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        if (\$request->input('action') === 'delete') {
            return \$this->delete(\$location);
        }

        \$this->updateService->handle(\$location->id, \$request->normalize());
        \$this->alert->success('Location was updated successfully.')->flash();

        return redirect()->route('admin.locations.view', \$location->id);
    }

    /**
     * Delete a location from the system.
     *
     * @throws \Exception
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function delete(Location \$location): RedirectResponse
    {
        // 🔒 Cegah akses selain admin ID 1
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        try {
            \$this->deletionService->handle(\$location->id);
            return redirect()->route('admin.locations');
        } catch (DisplayException \$ex) {
            \$this->alert->danger(\$ex->getMessage())->flash();
        }

        return redirect()->route('admin.locations.view', \$location->id);
    }
}"
    write_file "$BASE_DIR/app/Http/Controllers/Admin/LocationController.php" "$LOCATION_CONTROLLER"

    # ==========================================
    # 4. ANTI INTIP NODES
    # ==========================================
    NODE_CONTROLLER="<?php

namespace Pterodactyl\Http\Controllers\Admin\Nodes;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\Node;
use Spatie\QueryBuilder\QueryBuilder;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Contracts\View\Factory as ViewFactory;
use Illuminate\Support\Facades\Auth;

class NodeController extends Controller
{
    /**
     * NodeController constructor.
     */
    public function __construct(private ViewFactory \$view)
    {
    }

    /**
     * Returns a listing of nodes on the system.
     */
    public function index(Request \$request): View
    {
        // === 🔒 FITUR TAMBAHAN: Anti akses selain admin ID 1 ===
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }
        // ======================================================

        \$nodes = QueryBuilder::for(
            Node::query()->with('location')->withCount('servers')
        )
            ->allowedFilters(['uuid', 'name'])
            ->allowedSorts(['id'])
            ->paginate(25);

        return \$this->view->make('admin.nodes.index', ['nodes' => \$nodes]);
    }
}"
    write_file "$BASE_DIR/app/Http/Controllers/Admin/Nodes/NodeController.php" "$NODE_CONTROLLER"

    # ==========================================
    # 5. ANTI INTIP NEST
    # ==========================================
    NEST_CONTROLLER="<?php

namespace Pterodactyl\Http\Controllers\Admin\Nests;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Nests\NestUpdateService;
use Pterodactyl\Services\Nests\NestCreationService;
use Pterodactyl\Services\Nests\NestDeletionService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Nest\StoreNestFormRequest;
use Illuminate\Support\Facades\Auth;

class NestController extends Controller
{
    /**
     * NestController constructor.
     */
    public function __construct(
        protected AlertsMessageBag \$alert,
        protected NestCreationService \$nestCreationService,
        protected NestDeletionService \$nestDeletionService,
        protected NestRepositoryInterface \$repository,
        protected NestUpdateService \$nestUpdateService,
        protected ViewFactory \$view
    ) {
    }

    /**
     * Render nest listing page.
     *
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function index(): View
    {
        // 🔒 Proteksi: hanya user ID 1 (superadmin) yang bisa akses menu Nest
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        return \$this->view->make('admin.nests.index', [
            'nests' => \$this->repository->getWithCounts(),
        ]);
    }

    /**
     * Render nest creation page.
     */
    public function create(): View
    {
        return \$this->view->make('admin.nests.new');
    }

    /**
     * Handle the storage of a new nest.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     */
    public function store(StoreNestFormRequest \$request): RedirectResponse
    {
        \$nest = \$this->nestCreationService->handle(\$request->normalize());
        \$this->alert->success(trans('admin/nests.notices.created', ['name' => htmlspecialchars(\$nest->name)]))->flash();

        return redirect()->route('admin.nests.view', \$nest->id);
    }

    /**
     * Return details about a nest including all the eggs and servers per egg.
     *
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function view(int \$nest): View
    {
        return \$this->view->make('admin.nests.view', [
            'nest' => \$this->repository->getWithEggServers(\$nest),
        ]);
    }

    /**
     * Handle request to update a nest.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function update(StoreNestFormRequest \$request, int \$nest): RedirectResponse
    {
        \$this->nestUpdateService->handle(\$nest, \$request->normalize());
        \$this->alert->success(trans('admin/nests.notices.updated'))->flash();

        return redirect()->route('admin.nests.view', \$nest);
    }

    /**
     * Handle request to delete a nest.
     *
     * @throws \Pterodactyl\Exceptions\Service\HasActiveServersException
     */
    public function destroy(int \$nest): RedirectResponse
    {
        \$this->nestDeletionService->handle(\$nest);
        \$this->alert->success(trans('admin/nests.notices.deleted'))->flash();

        return redirect()->route('admin.nests');
    }
}"
    write_file "$BASE_DIR/app/Http/Controllers/Admin/Nests/NestController.php" "$NEST_CONTROLLER"

    # ==========================================
    # 6. ANTI INTIP SETTINGS
    # ==========================================
    SETTINGS_CONTROLLER="<?php

namespace Pterodactyl\Http\Controllers\Admin\Settings;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Helpers\SoftwareVersionService;
use Pterodactyl\Contracts\Repository\SettingsRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Settings\BaseSettingsFormRequest;

class IndexController extends Controller
{
    use AvailableLanguages;

    /**
     * IndexController constructor.
     */
    public function __construct(
        private AlertsMessageBag \$alert,
        private Kernel \$kernel,
        private SettingsRepositoryInterface \$settings,
        private SoftwareVersionService \$versionService,
        private ViewFactory \$view
    ) {
    }

    /**
     * Render the UI for basic Panel settings.
     */
    public function index(): View
    {
        // 🔒 Anti akses menu Settings selain user ID 1
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        return \$this->view->make('admin.settings.index', [
            'version' => \$this->versionService,
            'languages' => \$this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Handle settings update.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function update(BaseSettingsFormRequest \$request): RedirectResponse
    {
        // 🔒 Anti akses update settings selain user ID 1
        \$user = Auth::user();
        if (!\$user || \$user->id !== 1) {
            abort(403, '$WATERMARK');
        }

        foreach (\$request->normalize() as \$key => \$value) {
            \$this->settings->set('settings::' . \$key, \$value);
        }

        \$this->kernel->call('queue:restart');
        \$this->alert->success(
            'Panel settings have been updated successfully and the queue worker was restarted to apply these changes.'
        )->flash();

        return redirect()->route('admin.settings');
    }
}"
    write_file "$BASE_DIR/app/Http/Controllers/Admin/Settings/IndexController.php" "$SETTINGS_CONTROLLER"

    # ==========================================
    # 7. ANTI AKSES/INTIP SERVER
    # ==========================================

    # File A: FileController
    FILE_CONTROLLER="<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Response;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Models\Server;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Transformers\Api\Client\FileObjectTransformer;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CopyFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\PullFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\ListFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\ChmodFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\DeleteFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\RenameFileRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CreateFolderRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\CompressFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\DecompressFilesRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\GetFileContentsRequest;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\WriteFileContentRequest;

class FileController extends ClientApiController
{
    public function __construct(
        private NodeJWTService \$jwtService,
        private DaemonFileRepository \$fileRepository
    ) {
        parent::__construct();
    }

    /**
     * 🔒 Fungsi tambahan: Cegah akses server orang lain.
     */
    private function checkServerAccess(\$request, Server \$server)
    {
        \$user = \$request->user();

        // Admin (user id = 1) bebas akses semua
        if (\$user->id === 1) {
            return;
        }

        // Jika server bukan milik user, tolak akses
        if (\$server->owner_id !== \$user->id) {
            abort(403, '$WATERMARK');
        }
    }

    public function directory(ListFilesRequest \$request, Server \$server): array
    {
        \$this->checkServerAccess(\$request, \$server);

        \$contents = \$this->fileRepository
            ->setServer(\$server)
            ->getDirectory(\$request->get('directory') ?? '/');

        return \$this->fractal->collection(\$contents)
            ->transformWith(\$this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function contents(GetFileContentsRequest \$request, Server \$server): Response
    {
        \$this->checkServerAccess(\$request, \$server);

        \$response = \$this->fileRepository->setServer(\$server)->getContent(
            \$request->get('file'),
            config('pterodactyl.files.max_edit_size')
        );

        Activity::event('server:file.read')->property('file', \$request->get('file'))->log();

        return new Response(\$response, Response::HTTP_OK, ['Content-Type' => 'text/plain']);
    }

    public function download(GetFileContentsRequest \$request, Server \$server): array
    {
        \$this->checkServerAccess(\$request, \$server);

        \$token = \$this->jwtService
            ->setExpiresAt(CarbonImmutable::now()->addMinutes(15))
            ->setUser(\$request->user())
            ->setClaims([
                'file_path' => rawurldecode(\$request->get('file')),
                'server_uuid' => \$server->uuid,
            ])
            ->handle(\$server->node, \$request->user()->id . \$server->uuid);

        Activity::event('server:file.download')->property('file', \$request->get('file'))->log();

        return [
            'object' => 'signed_url',
            'attributes' => [
                'url' => sprintf(
                    '%s/download/file?token=%s',
                    \$server->node->getConnectionAddress(),
                    \$token->toString()
                ),
            ],
        ];
    }

    public function write(WriteFileContentRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        \$this->fileRepository->setServer(\$server)->putContent(\$request->get('file'), \$request->getContent());

        Activity::event('server:file.write')->property('file', \$request->get('file'))->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function create(CreateFolderRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        \$this->fileRepository
            ->setServer(\$server)
            ->createDirectory(\$request->input('name'), \$request->input('root', '/'));

        Activity::event('server:file.create-directory')
            ->property('name', \$request->input('name'))
            ->property('directory', \$request->input('root'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function rename(RenameFileRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        \$this->fileRepository
            ->setServer(\$server)
            ->renameFiles(\$request->input('root'), \$request->input('files'));

        Activity::event('server:file.rename')
            ->property('directory', \$request->input('root'))
            ->property('files', \$request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function copy(CopyFileRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        \$this->fileRepository
            ->setServer(\$server)
            ->copyFile(\$request->input('location'));

        Activity::event('server:file.copy')->property('file', \$request->input('location'))->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function compress(CompressFilesRequest \$request, Server \$server): array
    {
        \$this->checkServerAccess(\$request, \$server);

        \$file = \$this->fileRepository->setServer(\$server)->compressFiles(
            \$request->input('root'),
            \$request->input('files')
        );

        Activity::event('server:file.compress')
            ->property('directory', \$request->input('root'))
            ->property('files', \$request->input('files'))
            ->log();

        return \$this->fractal->item(\$file)
            ->transformWith(\$this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function decompress(DecompressFilesRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        set_time_limit(300);

        \$this->fileRepository->setServer(\$server)->decompressFile(
            \$request->input('root'),
            \$request->input('file')
        );

        Activity::event('server:file.decompress')
            ->property('directory', \$request->input('root'))
            ->property('files', \$request->input('file'))
            ->log();

        return new JsonResponse([], JsonResponse::HTTP_NO_CONTENT);
    }

    public function delete(DeleteFileRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        \$this->fileRepository->setServer(\$server)->deleteFiles(
            \$request->input('root'),
            \$request->input('files')
        );

        Activity::event('server:file.delete')
            ->property('directory', \$request->input('root'))
            ->property('files', \$request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function chmod(ChmodFilesRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        \$this->fileRepository->setServer(\$server)->chmodFiles(
            \$request->input('root'),
            \$request->input('files')
        );

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function pull(PullFileRequest \$request, Server \$server): JsonResponse
    {
        \$this->checkServerAccess(\$request, \$server);

        \$this->fileRepository->setServer(\$server)->pull(
            \$request->input('url'),
            \$request->input('directory'),
            \$request->safe(['filename', 'use_header', 'foreground'])
        );

        Activity::event('server:file.pull')
            ->property('directory', \$request->input('directory'))
            ->property('url', \$request->input('url'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }
}"
    write_file "$BASE_DIR/app/Http/Controllers/Api/Client/Servers/FileController.php" "$FILE_CONTROLLER"

    # File B: ServerController
    SERVER_CONTROLLER="<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Transformers\Api\Client\ServerTransformer;
use Pterodactyl\Services\Servers\GetUserPermissionsService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\GetServerRequest;

class ServerController extends ClientApiController
{
    /**
     * ServerController constructor.
     */
    public function __construct(private GetUserPermissionsService \$permissionsService)
    {
        parent::__construct();
    }

    /**
     * Transform an individual server into a response that can be consumed by a
     * client using the API.
     */
    public function index(GetServerRequest \$request, Server \$server): array
    {
        // 🔒 Anti intip server orang lain (kecuali admin ID 1)
        \$authUser = Auth::user();

        if (\$authUser->id !== 1 && (int) \$server->owner_id !== (int) \$authUser->id) {
            abort(403, '$WATERMARK');
        }

        return \$this->fractal->item(\$server)
            ->transformWith(\$this->getTransformer(ServerTransformer::class))
            ->addMeta([
                'is_server_owner' => \$request->user()->id === \$server->owner_id,
                'user_permissions' => \$this->permissionsService->handle(\$server, \$request->user()),
            ])
            ->toArray();
    }
}"
    write_file "$BASE_DIR/app/Http/Controllers/Api/Client/Servers/ServerController.php" "$SERVER_CONTROLLER"
    
    # Run artisan commands
    echo ""
    echo -e "${YELLOW}🔄 Running artisan commands...${NC}"
    cd $BASE_DIR
    
    php artisan cache:clear
    echo -e "${GREEN}✅ Cache cleared${NC}"
    
    php artisan view:clear
    echo -e "${GREEN}✅ View cache cleared${NC}"
    
    php artisan config:clear
    echo -e "${GREEN}✅ Config cache cleared${NC}"
    
    # Set permissions
    echo ""
    echo -e "${YELLOW}🔐 Setting permissions...${NC}"
    chown -R www-data:www-data $BASE_DIR
    chmod -R 755 $BASE_DIR/storage
    chmod -R 755 $BASE_DIR/bootstrap/cache
    echo -e "${GREEN}✅ Permissions set${NC}"
    
    # Restart Nginx
    echo ""
    echo -e "${YELLOW}🔄 Restarting Nginx...${NC}"
    sudo systemctl restart nginx
    echo -e "${GREEN}✅ Nginx was Restarted!${NC}"

    # Restart PHP
    echo ""
    echo -e "${YELLOW}🔄 Restarting PHP...${NC}"
    sudo systemctl restart php8.3-fpm
    echo -e "${GREEN}✅ PHP v8.3 was Restarted!${NC}"
    
    show_header
    echo -e "${GREEN}🎉 INSTALASI PROTECTION SELESAI!${NC}"
    echo "=========================================="
    echo ""
    echo -e "${GREEN}✅ Semua file protection telah diupdate${NC}"
    echo -e "${GREEN}✅ Backup file telah dibuat (.backup.*)${NC}"
    echo ""
    echo -e "${YELLOW}📋 **SUMMARY UPDATE YANG DILAKUKAN:**${NC}"
    echo "   - Updated: app/Services/Servers/ServerDeletionService.php"
    echo "   - Updated: app/Http/Controllers/Admin/UserController.php"
    echo "   - Updated: app/Http/Controllers/Admin/LocationController.php"
    echo "   - Updated: app/Http/Controllers/Admin/Nodes/NodeController.php"
    echo "   - Updated: app/Http/Controllers/Admin/Nests/NestController.php"
    echo "   - Updated: app/Http/Controllers/Admin/Settings/IndexController.php"
    echo "   - Updated: app/Http/Controllers/Api/Client/Servers/FileController.php"
    echo "   - Updated: app/Http/Controllers/Api/Client/Servers/ServerController.php"
    echo ""
    echo -e "${YELLOW}🔐 **PROTECTION AKTIF:**${NC}"
    echo "   ✅ Anti Delete Server"
    echo "   ✅ Anti Delete User" 
    echo "   ✅ Anti Intip Location"
    echo "   ✅ Anti Intip Nodes"
    echo "   ✅ Anti Intip Nest"
    echo "   ✅ Anti Intip Settings"
    echo "   ✅ Anti Akses Server Orang"
    echo ""
    echo -e "${BLUE}💡 Watermark saat ini: $WATERMARK${NC}"
    echo -e "${BLUE}📞 Support: t.me/ZarOffc${NC}"
    echo "=========================================="
}

# Function to change watermark
change_watermark() {
    show_header
    echo -e "${YELLOW}📝 CHANGE WATERMARK TEXT${NC}"
    echo "=========================================="
    echo ""
    echo -e "Watermark saat ini: ${BLUE}$WATERMARK${NC}"
    echo ""
    echo -e "Masukkan watermark text baru:"
    read -r new_watermark
    
    if [ -n "$new_watermark" ]; then
        # Update watermark in script itself
        sed -i "s|WATERMARK=.*|WATERMARK=\"$new_watermark\"|" "$0"
        echo -e "${GREEN}✅ Watermark berhasil diubah!${NC}"
        echo -e "${BLUE}Watermark baru: $new_watermark${NC}"
    else
        echo -e "${RED}❌ Watermark tidak boleh kosong!${NC}"
    fi
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Function to show menu
show_menu() {
    show_header
    echo -e "${BLUE}PILIH MENU:${NC}"
    echo "=========================================="
    echo -e "${GREEN}[1] Install Protection${NC}"
    echo -e "${YELLOW}[2] Change Watermark Text${NC}"
    echo -e "${RED}[3] Exit${NC}"
    echo "=========================================="
    echo -e "${BLUE}Current Watermark:${NC}"
    echo "$WATERMARK"
    echo "=========================================="
    echo -n "Pilih menu [1-3]: "
}

# Main script
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            install_protection
            ;;
        2)
            change_watermark
            ;;
        3)
            echo ""
            echo -e "${BLUE}👋 Terima kasih telah menggunakan script ini!${NC}"
            echo -e "${BLUE}📞 Support: t.me/ZarOffc${NC}"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Pilihan tidak valid!${NC}"
            sleep 2
            ;;
    esac
    
    echo ""
    read -p "Tekan Enter untuk melanjutkan..."
done
